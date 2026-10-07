import io

p = 'tests/Biotak_TH3_Test.mq4'
raw = io.open(p, encoding='utf-8', newline='').read()
norm = raw.replace('\r\n', '\n')
lines = norm.split('\n')

start = next(i for i, l in enumerate(lines) if 'the SPEC\'s names, verbatim' in l)
end = next(i for i, l in enumerate(lines) if '"Sample_001.png");' in l)
while lines[end].strip() != '}':
    end += 1

new = '''        // P-TH3-DB - ONE FOLDER PER SAMPLE, ONE COLUMN LIST. The folder NAME
        // and the header are behaviour, not comments: a reader, the sync tool
        // and this harness all key off them, so they are pinned here. Every
        // function below is pure - no chart, no file, no terminal.
        datetime when = StringToTime("2026.10.05 17:43");
        string folder = TH3SampleFolderName(when, "EURUSD", "M5", 15, "ABCD_Pattern_7040265");
        Check("db: the folder opens with the capture stamp",
              StringFind(folder, "20261005-1743_") == 0);
        Check("db: the folder carries symbol, timeframe and the counter",
              StringFind(folder, "_EURUSD_M5_S015_ABCD_Pattern_704") > 0);
        Check("db: the sample folder is TH3_Dataset/Samples/<name>",
              TH3SampleFolder(when, "EURUSD", "M5", 15, "") ==
              "TH3_Dataset/Samples/20261005-1743_EURUSD_M5_S015");
        // a name that reaches disk has to be a legal name, or the sample is lost
        Check("db: illegal filename characters are replaced",
              TH3SafeName("XAU/USD:M15*", 32) == "XAU_USD_M15_");
        Check("db: a long name is capped so the path stays short",
              StringLen(TH3SafeName("012345678901234567890123456789", 12)) == 12);
        // the global Dataset.csv and every per-sample sample.csv share ONE header
        string hdr[];
        TH3DatasetHeader(hdr);
        Check("db: the header owns exactly TH3_DATASET_COLS columns",
              ArraySize(hdr) == TH3_DATASET_COLS);
        Check("db: the row is keyed by sample and capture date",
              hdr[0] == "Sample_ID" && hdr[1] == "Capture_Date" && hdr[3] == "Capture_Stamp");
        Check("db: a reader groups by symbol and timeframe",
              hdr[4] == "Symbol" && hdr[5] == "TF" && hdr[6] == "Owner_TF");
        Check("db: the row carries the formula's answer and the market's",
              hdr[22] == "Step_Pips" && hdr[27] == "Actual_Turn" && hdr[28] == "Error_Pips");
        Check("db: the row points at the folder its own files live in",
              hdr[30] == "Folder" && hdr[31] == "Log_File" && hdr[32] == "Screenshot");
        // one stray comma would shift every later column of the row
        Check("db: a comma cannot enter a CSV field",
              TH3CsvField("ABCD, invented") == "ABCD  invented");
        // the global index, and the fallback that must NOT lose a sample
        Check("rec: the global DB is Dataset.csv under the tree",
              TH3RecorderPath(TH3_DATASET_DIR, TH3_DATASET_DB_NAME, true) == "TH3_Dataset/Dataset.csv");
        Check("rec: a refused folder still writes the leaf",
              TH3RecorderPath(TH3_DATASET_SHOTS, "Sample_001.png", false) == "Sample_001.png");'''.split('\n')

lines[start:end + 1] = new
out = '\n'.join(lines)
io.open(p, 'w', encoding='utf-8', newline='').write(out.replace('\n', '\r\n'))
print('harness pins replaced: %d lines -> %d' % (end - start + 1, len(new)))