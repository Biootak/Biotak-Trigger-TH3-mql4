# The TH3 dataset — one folder per sample, one database, one dashboard

Everything the recorder writes (key **M**) so the master-step formula can be tuned
against evidence instead of memory.

## Layout — a sample is a folder

```
MQL4\Files\TH3_Dataset\                 (terminal)
  Dataset.csv                          the global index, one row per sample
  Samples\
    20261005-1743_EURUSD_M5_S015_ABCD_Pattern_7040265\
      Sample_015.txt                   full diagnostics (the human record)
      Sample_015_EURUSD_M5.png         the chart as framed, 1:1
      sample.csv                       one row, same columns as Dataset.csv

Samples\TH3_Dataset\                   (repo — built by the sync)
  Dataset.csv                          rebuilt from the folders, sorted by capture time
  Reviews.csv                          Sample_ID,Verdict,Note,Reviewer,Reviewed_At
  journal.md                           append-only history of reviews and notes
  dashboard.html                       the page (images by relative path)
  Samples\<same folders>
```

The folder name is `<yyyymmdd-HHmm>_<SYMBOL>_<TF>_S<NNN>_<pattern>` — every part of
it is a fact the sample already carries, so the tree sorts by time with no
database, and the name is the key every tool parses. It is built by
`TH3SampleFolderName()` in [Biotak/TH3/TH3DatasetPaths.mqh](../Biotak/TH3/TH3DatasetPaths.mqh),
the one owner of the dataset's names, and pinned by `tests/Biotak_TH3_Test.mq4`.

A refused `FolderCreate` (a locked data folder) is **not** a lost sample: the
recorder falls back to the flat `Screenshots/`+`Logs/` pair and says which mode
wrote it in the TXT's `DATASET_PATH_MODE` line.

## The database — `Dataset.csv`, 33 columns

One list, written twice from one array by the recorder: into the sample's own
folder and into the global index, so the two cannot drift.

| group | columns |
|---|---|
| who/when | `Sample_ID`, `Capture_Date`, `Capture_Clock`, `Capture_Stamp`, `Symbol`, `TF`, `Owner_TF`, `Pattern`, `Direction` |
| the structure | `D_Time`, `D_Price`, `Digits`, `Pip_Size`, `Mother_Pips`, `Leg_AB`, `Leg_BC`, `Leg_CD`, `Ratio_BC_AB`, `Ratio_CD_BC`, `K` |
| the formula | `Step_Mother`, `Step_Pattern`, `Step_Pips`, `Target_1`, `Target_3`, `Target_5`, `Target_7` |
| the market | `Actual_Turn`, `Error_Pips`, `Rungs_Hit` |
| the files | `Folder`, `Log_File`, `Screenshot` |

`Reviews.csv` is deliberately **not** a column of that row: a verdict is a human
judgement that changes (`real → unclear → invented`), so it lives beside the
data, one current row per `Sample_ID`, and the journal keeps the history.

## The tools

```
node tools/th3-dataset-sync.js          # copy folders out of the terminal,
                                        # migrate any legacy flat samples,
                                        # rebuild Dataset.csv from the folders
node tools/th3-dataset-dashboard.js                    # build dashboard.html
node tools/th3-dataset-dashboard.js --inline           # one file, images inside
node tools/th3-dataset-dashboard.js review Sample_015 real    "clean AB=CD"
node tools/th3-dataset-dashboard.js review Sample_016 invented "no real turn"
node tools/th3-dataset-dashboard.js journal "K 3.5 looks high on XAU M15"
```

`review` writes the verdict, appends a timestamped line to `journal.md`, and
rebuilds the page. The dashboard's verdict buttons copy the exact command to the
clipboard — a browser cannot write to disk over `file://`, so the write is the
user's one command, and the page says so instead of pretending.

The dashboard answers the question the set is read for: how the formula does
**as a set** — median/mean error, the share within 5 pips, the error histogram,
and mean/median/worst per symbol·timeframe — with every sample kept separate
below, filterable by symbol, timeframe, verdict, date and error.

## Why the sync is a script

`FileOpen` is sandboxed to `<terminal data>\MQL4\Files` and `WebRequest` returns
error 4060 from an indicator (one thread per symbol, shared by every chart), so
nothing inside MT4 can move these files into the repo or to the cloud. The
recorder writes once where it can; the copy is the user's side. Images are
compressed only losslessly (indexed PNG, verified pixel-identical, max deviation
0) and the tool reports the running total against GitHub's 1 GB ceiling.