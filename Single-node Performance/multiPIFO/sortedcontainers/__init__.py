from bisect import bisect_left as _bisect_left


class SortedList:
    def __init__(self, iterable=None):
        self._items = []
        if iterable is not None:
            for item in iterable:
                self.add(item)

    def add(self, item):
        self._items.insert(_bisect_left(self._items, item), item)

    def pop(self, index=-1):
        return self._items.pop(index)

    def remove(self, item):
        self._items.remove(item)

    def clear(self):
        self._items.clear()

    def bisect_left(self, item):
        return _bisect_left(self._items, item)

    def __bool__(self):
        return bool(self._items)

    def __len__(self):
        return len(self._items)

    def __iter__(self):
        return iter(self._items)

    def __getitem__(self, index):
        return self._items[index]
