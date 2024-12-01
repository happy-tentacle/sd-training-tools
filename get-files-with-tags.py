import argparse
import os
from waifuc.source import LocalSource
from waifuc.action import (
    TagFilterAction,
    TagRemoveUnderlineAction,
    TaggingAction,
)

from actions import TagFilterAnyOfAction
from exporters import FileNameExporter
from tqdm import tqdm
from functools import partialmethod

tqdm.__init__ = partialmethod(tqdm.__init__, disable=True)

# Example:
# python .\get-files-with-tags.py --input "T:\..." --recursive --tag-all-of "green hair" "1girl" | % { Copy-Item -LiteralPath $_ -Destination "T:\..." }

parser = argparse.ArgumentParser(
    prog="Lora training script",
    description="Takes care of extracting, tagging, and deduplicating character images from video files",
)

parser.add_argument("--input", dest="input", required=True)
parser.add_argument(
    "--recursive",
    dest="recursive",
    action="store_true",
    help="Traverse input directory recursively",
    default=False,
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
args = parser.parse_args()

min_size: int = args.min_size
input: str = args.input
recursive: bool = args.recursive
tag_any_of: list[str] = args.tag_any_of
tag_all_of: list[str] = args.tag_all_of
tag_none_of: list[str] = args.tag_none_of
tag_confidence: float = args.tag_confidence

if __name__ == "__main__":
    if os.path.isdir(input):
        source = LocalSource(input)
    else:
        raise Exception("Input is not a directory")

    source = source.attach(
        # Tag images
        TaggingAction(
            method="wd14_v3_swinv2",
            force=True,
            general_threshold=0.35,
            character_threshold=2,  # don't add character tags, e.g. "shimakaze \(kancolle\)"
            drop_overlap=True,  # drop overlapping tags
        ),
        # Remove underlines from tags
        TagRemoveUnderlineAction(),
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

    exporter = FileNameExporter()
    source.export(exporter)