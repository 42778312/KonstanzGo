#!/bin/sh
# Rebuilds every offline data file the app ships, into App/Resources/Data/.
# Inputs are the files under */data/ (not in git; see README.md for where they come from).
#
#     DataPipeline/build.sh
set -eu
cd "$(dirname "$0")"

if [ ! -x .venv/bin/python ]; then
    python3 -m venv .venv
    .venv/bin/pip install -q -r requirements.txt
fi
PY=.venv/bin/python

echo "1/5 timetable"; $PY gtfs-import/import_gtfs.py
echo "2/5 places";    $PY places-import/import_places.py
echo "3/5 search";    $PY places-import/build_search.py
echo "4/5 walking";   $PY walk-graph/build_graph.py
echo "5/5 map style"; $PY map/make_style.py
cp map/data/konstanz.pmtiles ../App/Resources/Data/map/konstanz.pmtiles

$PY check.py
