Saved-variables files with GatherMap recordings go here, to be baked into
the next release: `WTF/Account/<name>/SavedVariables/GatherMap.lua`, renamed
to anything ending in `.lua` (one per player). The build reads them all:
their new points join the spawns, their gathers mark spawns confirmed, and a
spawn someone marked "not here" and nobody gathered is left out.
