from typing import Iterator, List, Mapping, Union
from waifuc.action import ProcessAction
from waifuc.model import ImageItem
from waifuc.action import TaggingAction, BaseAction


class TagAddAction(ProcessAction):
    def __init__(self, tags_to_add: List[str]):
        self.tags_to_add = tags_to_add

    def process(self, item: ImageItem) -> ImageItem:
        tags = dict(item.meta.get("tags") or {})
        tag_weight = 1
        for tag_to_add in reversed(self.tags_to_add):
            tags[tag_to_add] = tag_weight
            tag_weight += 0.01  # Add weight to preserve input tag ordering
        return ImageItem(item.image, {**item.meta, "tags": tags})


class TagFilterAnyOfAction(BaseAction):
    def __init__(
        self,
        tags: Union[List[str], Mapping[str, float]],
        method: str = "wd14_convnextv2",
        reversed: bool = False,
        **kwargs,
    ):
        if isinstance(tags, (list, tuple)):
            self.tags = {tag: 1e-6 for tag in tags}
        elif isinstance(tags, dict):
            self.tags = dict(tags)
        else:
            raise TypeError(f"Unknown type of tags - {tags!r}.")
        self.tagger = TaggingAction(method, force=False, **kwargs)
        self.reversed = reversed

    def iter(self, item: ImageItem) -> Iterator[ImageItem]:
        item = self.tagger(item)
        tags = item.meta["tags"]

        valid = self.reversed
        for tag, min_score in self.tags.items():
            tag_score = tags.get(tag, 0.0)
            if (not self.reversed and tag_score > min_score) or (
                self.reversed and tag_score < min_score
            ):
                valid = not self.reversed
                break

        if valid:
            yield item

    def reset(self):
        self.tagger.reset()
