import io

# --- TH3DatasetPaths.mqh: no 2-arg TimeToString, no StringReplace on a const
p = 'Biotak/TH3/TH3DatasetPaths.mqh'
s = io.open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert old in s, old[:80]
    s = s.replace(old, new, 1)


rep('''string TH3SampleStamp(const datetime when)
{
   string d = TH3SafeName(StringReplace(TimeToString(when, TIME_DATE), ".", ""), 8);
   string t = TH3SafeName(StringReplace(TimeToString(when, TIME_MINUTES), ":", ""), 4);
   return d + "-" + t;
}''',
    '''string TH3SampleStamp(const datetime when)
{
   //--- NOT TimeToString(when, TIME_DATE): this build resolves that two-argument
   //--- form as a symbol, not the builtin (compile error 137), and a folder name
   //--- has to be locale-free anyway - a German or Persian terminal would spell
   //--- the same capture differently. So the stamp is formatted from the integer
   //--- parts, which is pure, exact, and identical on every machine.
   return StringFormat("%04d%02d%02d-%02d%02d",
                       TimeYear(when), TimeMonth(when), TimeDay(when),
                       TimeHour(when), TimeMinute(when));
}

//+------------------------------------------------------------------+
//| The same stamp split for the database: the day, and the clock.   |
//| The dashboard groups by these, so they must be plain text a     |
//| spreadsheet sorts - not "2026.10.05 17:43" in one field.        |
//+------------------------------------------------------------------+
string TH3SampleDate(const datetime when)
{
   return StringFormat("%04d.%02d.%02d", TimeYear(when), TimeMonth(when), TimeDay(when));
}

string TH3SampleClock(const datetime when)
{
   return StringFormat("%02d:%02d", TimeHour(when), TimeMinute(when));
}''')

rep('''string TH3CsvField(const string raw)
{
   string s = StringReplace(raw, ",", " ");''',
    '''string TH3CsvField(const string raw)
{
   string s = raw;                    // StringReplace takes its input by reference
   s = StringReplace(s, ",", " ");''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)

# --- TH3Recorder.mqh: the same, at the three call sites
p = 'Biotak/TH3Recorder.mqh'
s = io.open(p, encoding='utf-8').read()
rep('''   row[1]  = TimeToString(capAt, TIME_DATE);
   row[2]  = TimeToString(capAt, TIME_MINUTES);''',
    '''   row[1]  = TH3SampleDate(capAt);
   row[2]  = TH3SampleClock(capAt);''')
rep('''      FileWrite(fh, "CAPTURE_TIME: " + TimeToString(capAt, TIME_DATE|TIME_SECONDS));''',
    '''      FileWrite(fh, "CAPTURE_TIME: " + TimeToString(capAt));''')
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('compile errors addressed')