from dataclasses import dataclass, field
from collections.abc import Callable

@dataclass
class Test:
    id: str
    fun: Callable

    def __call__ (self, *args):
        return self.fun(*args)
