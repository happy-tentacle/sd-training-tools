import logging
import os
import sys
from typing import Any, Mapping, Optional
from waifuc.export import BaseExporter, LocalDirectoryExporter
from waifuc.model import ImageItem
from imgutils.tagging import tags_to_text


class FileNameExporter(BaseExporter):
    filenames: list[str] = []

    def __init__(
        self, filenames: list[str] = None, ignore_error_when_export: bool = False
    ):
        BaseExporter.__init__(self, ignore_error_when_export)
        if filenames is not None:
            self.filenames = filenames

    def pre_export(self):
        pass

    def post_export(self):
        pass

    def export_item(self, item: ImageItem):
        if "path" in item.meta:
            self.filenames.append(item.meta["path"])
            print(item.meta["path"], file=sys.stdout, flush=True)

    def reset(self):
        pass

    def __deepcopy__(self, memo):
        # source.export creates a deepcopy of the exporter so we need to override __deepcopy__ to reuse the same dicts
        return FileNameExporter(self.filenames, self.ignore_error_when_export)


class TagValidatorExporter(BaseExporter):
    def __init__(
        self, tag_frequency: dict[str, int], ignore_error_when_export: bool = False
    ):
        BaseExporter.__init__(self, ignore_error_when_export)
        self.tag_frequency = tag_frequency

    def pre_export(self):
        pass

    def post_export(self):
        pass

    def export_item(self, item: ImageItem):
        tags = item.meta.get("tags", None) or {}
        for tag in tags:
            tag_count = self.tag_frequency.get(tag)
            self.tag_frequency[tag] = tag_count + 1 if tag_count else 1

    def reset(self):
        pass

    def __deepcopy__(self, memo):
        # source.export creates a deepcopy of the exporter so we need to override __deepcopy__ to reuse the same dicts
        return TagValidatorExporter(self.tag_frequency, self.ignore_error_when_export)


class ChainedExporter(BaseExporter):
    def __init__(self, exporters: list[BaseExporter]):
        self.exporters = exporters

    def pre_export(self):
        for exporter in self.exporters:
            exporter.pre_export()

    def post_export(self):
        for exporter in self.exporters:
            exporter.post_export()

    def export_item(self, item: ImageItem):
        for exporter in self.exporters:
            exporter.export_item(item)

    def reset(self):
        for exporter in self.exporters:
            exporter.reset()


class TextualInversionExporter(LocalDirectoryExporter):
    def __init__(
        self,
        output_dir: str,
        clear: bool = False,
        use_spaces: bool = False,
        use_escape: bool = True,
        include_score: bool = False,
        score_descend: bool = True,
        skip_image_export: bool = False,
        skip_when_image_exist: bool = False,
        ignore_error_when_export: bool = False,
        save_params: Optional[Mapping[str, Any]] = None,
        organize_by_tags: list[str] = None
    ):
        LocalDirectoryExporter.__init__(
            self, output_dir, clear, ignore_error_when_export
        )
        self.use_spaces = use_spaces
        self.use_escape = use_escape
        self.include_score = include_score
        self.score_descend = score_descend
        self.untitles = 0
        self.skip_image_export = skip_image_export
        self.skip_when_image_exist = skip_when_image_exist
        self.save_params = save_params or {}
        self.organize_by_tags = organize_by_tags or []

    def export_item(self, item: ImageItem):
        if "filename" in item.meta:
            filename = item.meta["filename"]
        else:
            self.untitles += 1
            filename = f"untitled_{self.untitles}.png"

        tags = item.meta.get("tags", None) or {}

        output_dir = self.output_dir
        if len(self.organize_by_tags) > 0:
            tags: dict[str, float] = item.meta.get("tags", None)
            for tag in self.organize_by_tags:
                if tag in tags:
                    output_dir = os.path.join(output_dir, tag)
                    break

        full_filename = os.path.join(output_dir, filename)
        full_tagname = os.path.join(
            output_dir, os.path.splitext(filename)[0] + ".txt"
        )
        full_directory = os.path.dirname(full_filename)
        if full_directory:
            os.makedirs(full_directory, exist_ok=True)

        if not self.skip_image_export:
            if not self.skip_when_image_exist or not os.path.exists(full_filename):
                item.image.save(full_filename, **(self.save_params or {}))

        with open(full_tagname, "w", encoding="utf-8") as f:
            f.write(
                tags_to_text(
                    tags,
                    self.use_spaces,
                    self.use_escape,
                    self.include_score,
                    self.score_descend,
                )
            )

    def reset(self):
        self.untitles = 0
