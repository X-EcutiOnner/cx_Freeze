"""A collection of functions which are triggered automatically by finder when
matplotlib package is included.
"""

from __future__ import annotations

from pathlib import Path
from types import CodeType

from ..common import code_object_replace_function
from ..finder import ModuleFinder
from ..module import Module


def load_matplotlib(finder: ModuleFinder, module: Module) -> None:
    """The matplotlib package requires mpl-data subdirectory."""
    module_path = module.file.parent
    target_path = Path("lib", module.name, "mpl-data")
    # mpl-data is always in a subdirectory in matplotlib >= 3.4
    data_path = module_path / "mpl-data"
    if not data_path.is_dir():
        data_path = __import__("matplotlib").get_data_path()
        _patch_data_path(module, target_path)
    elif module.in_file_system == 0:  # zip_include_packages
        _patch_data_path(module, target_path)
    finder.include_files(data_path, target_path, copy_dependent_files=False)
    finder.include_package("matplotlib")
    finder.exclude_module("matplotlib.tests")
    finder.exclude_module("matplotlib.testing")
    # matplotlib >= 3.7 uses an additional library directory
    module_libs_name = "matplotlib.libs"
    source_dir = module_path.parent / module_libs_name
    if source_dir.exists():
        finder.include_files(source_dir, f"lib/{module_libs_name}")
    _remove_delvewheel(module)
    mpl_toolkits = finder.include_module("mpl_toolkits")
    _remove_delvewheel(mpl_toolkits)


def _patch_data_path(module: Module, data_path: Path) -> None:
    # fix get_data_path functions when using zip_include_packages or
    # with some distributions that have matplotlib < 3.4 installed.
    if module.code is None:
        return
    code = module.code
    for name in ("_get_data_path", "get_data_path"):
        source = f"""\
        def {name}():
            import os, sys
            return os.path.join(sys.frozen_dir, "{data_path}")
        """
        # pacth if the name (_get_data_path and/or get_data_path) is found
        code = code_object_replace_function(code, name, source)
    module.code = code


def _remove_delvewheel(module: Module) -> None:
    # remove delvewheel injections of code to not find for .libs directory
    if module.code is None:
        return
    code = module.code
    delvewheel_func = "_delvewheel_init_patch_"
    consts = list(code.co_consts)
    for constant in consts:
        if isinstance(constant, CodeType):
            name = constant.co_name
            if name.startswith(delvewheel_func):
                break
    source = f"""\
    def {name}():
        return
    """
    module.code = code_object_replace_function(code, name, source)