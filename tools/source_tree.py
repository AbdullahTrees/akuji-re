"""Locate source files without depending on their physical category folder."""

import os


SKIP_DIRS = {'backup', 'lib'}


def source_files(repo, suffixes=('.pas', '.lpr', '.inc')):
    """Return source files recursively, in a stable order."""
    root = os.path.join(repo, 'src')
    found = []
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d.lower() not in SKIP_DIRS)
        for name in files:
            if name.lower().endswith(suffixes):
                found.append(os.path.join(directory, name))
    return sorted(found, key=lambda path: os.path.relpath(path, root).lower())


def unit_path(repo, name):
    """Resolve a Pascal unit by its unique file name."""
    matches = [path for path in source_files(repo)
               if os.path.basename(path).lower() == name.lower()]
    if len(matches) != 1:
        raise ValueError('expected one source file named %s, found %d'
                         % (name, len(matches)))
    return matches[0]


def source_name(repo, path):
    """Return a stable, slash-separated path relative to src/."""
    return os.path.relpath(path, os.path.join(repo, 'src')).replace(os.sep, '/')
