import argparse
import os
from waifuc.export import SaveExporter
from waifuc.source import VideoSource, LocalSource
from waifuc.action import (
    PersonSplitAction,
    MinSizeFilterAction,
    TagFilterAction,
    TagDropAction,
    BlacklistedTagDropAction,
    FilterSimilarAction,
    TagRemoveUnderlineAction,
    TaggingAction,
)

from actions import TagAddAction, TagFilterAnyOfAction
from exporters import ChainedExporter, TextualInversionExporter

# Examples
#
# Extract frames from video:
# python .\process.py --input-type video --input "T:\stablediffusion\datasets\delilah\test" \
#   --output "T:\stablediffusion\datasets\delilah\test"
#
# Process image tags:
# python .\process.py --input-type image --input "T:\stablediffusion\datasets\delilah\test" \
#   --output "T:\stablediffusion\datasets\delilah\test" --skip-person-split --overwrite-tags \
#   --add-tags ht_delilah delilah_warrior \
#   --drop-tags "dark-skinned female" "dark skin" "animal ears" "furry female" "furry"

parser = argparse.ArgumentParser(
    prog="Lora training script",
    description="Takes care of extracting, tagging, and deduplicating character images from video files",
)

parser.add_argument("--input", dest="input", required=True)
parser.add_argument("--output", dest="output", required=False)
parser.add_argument(
    "--input-type",
    dest="input_type",
    choices=["video", "image"],
    default="video",
    help="Type of input file to process",
)
parser.add_argument(
    "--recursive",
    dest="recursive",
    action="store_true",
    help="Traverse input directory recursively",
    default=False,
)
parser.add_argument(
    "--output-meta",
    dest="output_meta",
    choices=["txt", "json", "all", "none"],
    default="all",
    help="Type of metadata output for textual inversion",
)
parser.add_argument(
    "--add-tags",
    dest="add_tags",
    nargs="+",
    help="Extra tags to add to the textual inversion output",
)
parser.add_argument(
    "--drop-tags",
    dest="drop_tags",
    nargs="+",
    help="Extra tags to drop from the textual inversion output",
)
parser.add_argument(
    "--overwrite-tags",
    dest="overwrite_tags",
    action="store_true",
    help="Overwite existing tags if any",
)
parser.add_argument(
    "--split-person",
    dest="split_person",
    action="store_true",
    help="Split images by person",
)
parser.add_argument(
    "--tag-all-of",
    dest="tag_all_of",
    help="Process images that have all of the given tags",
    nargs="+",
)
parser.add_argument(
    "--tag-none-of",
    dest="tag_none_of",
    help="Process images that have none of the given tags",
    nargs="+",
)
parser.add_argument(
    "--tag-any-of",
    dest="tag_any_of",
    help="Process images that have any of the given tags",
    nargs="+",
)
parser.add_argument(
    "--tag-confidence",
    dest="tag_confidence",
    help="Confidence threshold for tag filtering in the range [0-1]",
    default=0.6,
)
parser.add_argument(
    "--min-size",
    dest="min_size",
    help="Minimum image size (for both width and height)",
    default=480,
)
parser.add_argument(
    "--tag-only",
    dest="tag_only",
    action="store_true",
    help="Only run tagger, do not manipulate images",
    default=False,
)
parser.add_argument(
    "--organize-by-tags",
    dest="organize_by_tags",
    help="Organize output images in folders based on the given tags",
    nargs="+",
)

args = parser.parse_args()

min_size: int = args.min_size
add_tags: list[str] = args.add_tags
drop_tags: list[str] = args.drop_tags
input: str = args.input
input_type: str = args.input_type
recursive: bool = args.recursive
output: str = args.output
output_meta: str = args.output_meta
overwrite_tags: bool = args.overwrite_tags
split_person: bool = args.split_person
tag_any_of: list[str] = args.tag_any_of
tag_all_of: list[str] = args.tag_all_of
tag_none_of: list[str] = args.tag_none_of
tag_confidence: float = args.tag_confidence
tag_only: bool = args.tag_only
organize_by_tags: list[str] = args.organize_by_tags

# See https://deepghs.github.io/waifuc/main/tutorials/crawl_videos/index.html
# See https://deepghs.github.io/waifuc/main/tutorials/process_images/index.html#common-actions-and-usage-examples
# Make sure the following are installed first:
# - https://developer.nvidia.com/cudnn-downloads?target_os=Windows&target_arch=x86_64&target_version=10&target_type=exe_local
# - https://developer.nvidia.com/cuda-downloads?target_os=Windows&target_arch=x86_64&target_version=11&target_type=exe_local
if __name__ == "__main__":
    if input_type == "video":
        if os.path.isdir(input):
            source = VideoSource.from_directory(
                input, min_frame_interval=0.25, recursive=recursive
            )
        else:
            source = VideoSource(input, min_frame_interval=0.25)
    elif input_type == "image":
        if os.path.isdir(input):
            source = LocalSource(input)
        else:
            raise Exception("Input is not a directory")
    else:
        raise Exception("Unknown input type: " + input_type)

    if split_person:
        source = source.attach(PersonSplitAction(conf_threshold=0.5))

    if not tag_only:
        source = source.attach(
            # Keep images with at least 320px of width and height
            MinSizeFilterAction(min_size),
            # Remove images similar to the last 5 captured
            FilterSimilarAction(capacity=5),
        )

    source = source.attach(
        # Tag images
        TaggingAction(
            method="wd14_v3_swinv2",
            force=overwrite_tags,
            general_threshold=0.35,
            character_threshold=2,  # don't add character tags, e.g. "shimakaze \(kancolle\)"
            drop_overlap=True,  # drop overlapping tags
        ),
        # Remove underlines from tags
        TagRemoveUnderlineAction(),
        # Discard blacklisted tags
        # See https://huggingface.co/datasets/alea31415/tag_filtering/blob/main/blacklist_tags.txt
        BlacklistedTagDropAction(),
    )

    if not tag_only:
        source = source.attach(
            # # Split images into full body, upper body, and head
            # ThreeStageSplitAction(),
            # Discard images with bad quality tags
            TagFilterAction({"blurry": 0.8, "dark": 0.9}, reversed=True)
        )

    if tag_any_of:
        source = source.attach(
            TagFilterAnyOfAction(
                {tag.replace("_", " "): tag_confidence for tag in tag_any_of}
            )
        )

    if tag_all_of:
        source = source.attach(
            TagFilterAction(
                {tag.replace("_", " "): tag_confidence for tag in tag_all_of}
            )
        )

    if tag_none_of:
        source = source.attach(
            TagFilterAction(
                {tag.replace("_", " "): tag_confidence for tag in tag_none_of},
                reversed=True,
            )
        )

    if add_tags:
        source = source.attach(TagAddAction(tag.replace("_", " ") for tag in add_tags))

    if drop_tags:
        source = source.attach(
            TagDropAction(tag.replace("_", " ") for tag in drop_tags)
        )

    if not output:
        if tag_only:
            output = os.path.dirname(input) if os.path.isfile(input) else input
        elif os.path.isdir(input):
            output = os.path.join(input, "output")
        else:
            output = os.path.join(os.path.dirname(input), "output")

    if output_meta == "txt":
        source.export(
            TextualInversionExporter(
                output,
                skip_when_image_exist=True,
                skip_image_export=tag_only,
                use_spaces=True,
                organize_by_tags=organize_by_tags
            )
        )
    elif output_meta == "json":
        source.export(SaveExporter(output))
    elif output_meta == "all":
        source.export(
            ChainedExporter(
                [
                    SaveExporter(output, skip_when_image_exist=True),
                    TextualInversionExporter(
                        output, skip_when_image_exist=True, use_spaces=True, organize_by_tags=organize_by_tags
                    ),
                ]
            )
        )
    elif output_meta == "none":
        source.export(SaveExporter(output, no_meta=True))
