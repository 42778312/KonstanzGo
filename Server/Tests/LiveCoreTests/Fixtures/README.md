# EFA-BW fixtures

Raw responses of EFA-BW's departure monitor, recorded by `Server/scripts/record_fixtures.py` (one request every 2 s).
Tests read only these files; no test or CI job ever calls EFA-BW.

`timetable-20261011.db` is a copy of the timetable these responses were matched against, so the golden match test
gives the same answer after the app's timetable is refreshed.

## Request

```
https://www.efa-bw.de/nvbw/XML_DM_REQUEST?outputFormat=rapidJSON&type_dm=stop&mode=direct&useRealtime=1
    &depType=stopEvents&name_dm=<stop gid>&limit=40
```

`rapidJSON`, not `JSON`: the two formats are shaped differently, and the app's parser (`KGCore/Live/LiveDepartures.swift`)
already reads `rapidJSON`.

## Fields, from the recorded responses

All paths are inside one element of `stopEvents[]`. Times are ISO 8601 in UTC (`2026-11-13T10:13:00Z`).

| What | JSON path | Seen |
|---|---|---|
| Planned time | `departureTimePlanned` | always (also `departureTimeBaseTimetable`, same value so far) |
| Real time | `departureTimeEstimated` | only when monitored: 133 of 206 departures |
| Delay | not sent: `departureTimeEstimated − departureTimePlanned` | |
| Line number | `transportation.number` (`"12"`, `"9"`); `transportation.disassembledName` is the same | always |
| Destination | `transportation.destination.name` | always |
| Platform | `location.id` (DHID, `de:08335:11918:0:2`); `location.properties.platformName` (`"Bstg. 2"`) | always |
| Stop gid | `location.parent.id` (`de:08335:11918`); the request's stop is `locations[0].id` | always |
| Realtime status | `realtimeStatus` (`["MONITORED"]`), `isRealtimeControlled` | on monitored departures only |
| Cancellation | `isCancelled`, or `TRIP_CANCELLED` in `realtimeStatus` | **not seen** in these recordings |
| Product | `transportation.product.class`: 5 city bus, 6 regional bus, 1 S-Bahn, 13 regional train | always |
| Trip id | `properties.AVMSTripID` (`131126-18854400`): unrelated to the timetable's ids, not used | most |

## Surprises

- Asking for the bus stop of Konstanz Bahnhof (`de:08335:11882`) returns departures at platform `de:08335:6554:10:1`,
  in the train station's area. The server maps platforms to stations through the timetable, never by gid string.
- EFA-BW names lines 9A and 9B both `"9"`. The timetable keeps them apart, so the matcher tries the lettered
  variants of a line at the same stop and minute when the line itself has no trip there.
- `transportation.origin.id` and `destination.id` are EFA-BW's numeric ids (`8711934`). They are not stable and are
  never used (plan rule 6).

## Recordings

| Run | When | Files |
|---|---|---|
| 1 | Fri 13 Nov 2026, 11:12 | 6 |
| 2 | weekday morning rush | to do |
| 3 | late night | to do |
