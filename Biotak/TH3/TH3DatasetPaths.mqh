//+------------------------------------------------------------------+
//| TH3/TH3DatasetPaths.mqh                                          |
//| P-TH3-REC — THE DATASET TREE, BY OWNER.                          |
//|                                                                  |
//| The recorder's paths are BEHAVIOUR, not text: a reader looking in |
//| MQL4\Files\TH3_Dataset\Logs must find Sample_###.txt where the    |
//| spec says. This file is the ONE home for those paths so the      |
//| recorder and the harness cannot disagree about where a sample     |
//| lands. It is PURE: two string constants, one joiner, no chart     |
//| reads and no objects — which is also what makes it harness-safe   |
//| (P-BUILD-02: Biotak_TH3_Test.mq4 cannot include the recorder      |
//| itself, because that pulls TH3Pivots_A/TH3Tool_A and the whole   |
//| chart chain with it).                                             |
//|                                                                  |
//| MQL4 has no mkdir; the terminal's own FolderCreate is the only    |
//| way and it takes a path RELATIVE to MQL4\Files. It is idempotent  |
//| and returns 0 when the folder already exists, so these calls are |
//| safe on every press. A refusal is NOT fatal: `dirsOk` goes false  |
//| and every path then drops its prefix, so a locked-down data       |
//| folder still records the sample rather than losing it.            |
//+------------------------------------------------------------------+
#ifndef TH3_DATASET_PATHS_MQH
#define TH3_DATASET_PATHS_MQH
#property strict

#define TH3_DATASET_DIR      "TH3_Dataset"
#define TH3_DATASET_SHOTS    "TH3_Dataset/Screenshots"
#define TH3_DATASET_LOGS     "TH3_Dataset/Logs"
#define TH3_RECORDER_MAX     100

//+------------------------------------------------------------------+
//| The tree, and whether it took. `dirsOk` is the recorder's only   |
//| answer to "did the folders appear" — it is passed by reference so |
//| the caller can name the mode in its own output (the TXT says which |
//| path mode wrote it, so a flat fallback is never mistaken for the  |
//| tree).                                                          |
//+------------------------------------------------------------------+
void TH3RecorderEnsureDirs(bool &dirsOk)
{
   dirsOk = true;
   if(FolderCreate(TH3_DATASET_SHOTS) < 0) dirsOk = false;
   if(FolderCreate(TH3_DATASET_LOGS)  < 0) dirsOk = false;
   if(dirsOk && FolderCreate(TH3_DATASET_DIR) < 0) dirsOk = false;
}

//+------------------------------------------------------------------+
//| One joiner, so the tree prefix and the fallback are the SAME rule |
//| on both sides. Pure: string in, string out.                     |
//+------------------------------------------------------------------+
string TH3RecorderPath(const string dir, const string leaf, const bool dirsOk)
{
   return dirsOk ? (dir + "/" + leaf) : leaf;
}

#endif // TH3_DATASET_PATHS_MQH
