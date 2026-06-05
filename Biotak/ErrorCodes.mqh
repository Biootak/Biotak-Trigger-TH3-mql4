  //+------------------------------------------------------------------+
//|                                                   ErrorCodes.mqh |
//|                                  GOLD VERSION: Unified Errors    |
//|                                  Centralized Error Management    |
//+------------------------------------------------------------------+
#property copyright "  Biotak - GOLD Version"
#property strict

#ifndef ERROR_CODES_MQH
#define ERROR_CODES_MQH

//+------------------------------------------------------------------+
//| Error Code Categories                                            |
//+------------------------------------------------------------------+
enum ENUM_ERROR_CATEGORY {
    ERR_CAT_NONE = 0,
    ERR_CAT_VALIDATION = 1000,
    ERR_CAT_CALCULATION = 2000,
    ERR_CAT_MEMORY = 3000,
    ERR_CAT_IO = 4000,
    ERR_CAT_RENDERING = 5000
};

//+------------------------------------------------------------------+
//| Validation Errors (1000-1999)                                    |
//+------------------------------------------------------------------+
#define ERR_INVALID_PRICE           1001
#define ERR_INVALID_PERCENTAGE      1002
#define ERR_INVALID_ARRAY_SIZE      1003
#define ERR_INVALID_PARAMETER       1004
#define ERR_OUT_OF_RANGE            1005

//+------------------------------------------------------------------+
//| Calculation Errors (2000-2999)                                   |
//+------------------------------------------------------------------+
#define ERR_DIVISION_BY_ZERO        2001
#define ERR_OVERFLOW                2002
#define ERR_PRECISION_LOSS          2003
#define ERR_INVALID_RESULT          2004

//+------------------------------------------------------------------+
//| Memory Errors (3000-3999)                                        |
//+------------------------------------------------------------------+
#define ERR_BUFFER_OVERFLOW         3001
#define ERR_MEMORY_ALLOCATION       3002
#define ERR_ARRAY_RESIZE            3003
#define ERR_MEMORY_LEAK             3004

//+------------------------------------------------------------------+
//| I/O Errors (4000-4999)                                           |
//+------------------------------------------------------------------+
#define ERR_FILE_NOT_FOUND          4001
#define ERR_FILE_READ               4002
#define ERR_FILE_WRITE              4003
#define ERR_FILE_CORRUPT            4004

//+------------------------------------------------------------------+
//| Rendering Errors (5000-5999)                                     |
//+------------------------------------------------------------------+
#define ERR_OBJECT_CREATE           5001
#define ERR_OBJECT_UPDATE           5002
#define ERR_OBJECT_DELETE           5003
#define ERR_RACE_CONDITION          5004

//+------------------------------------------------------------------+
//| Get Error Message                                                |
//+------------------------------------------------------------------+
string GetErrorMessage(int errorCode) {
    switch(errorCode) {
        // Validation
        case ERR_INVALID_PRICE: return "Invalid price value";
        case ERR_INVALID_PERCENTAGE: return "Invalid percentage value";
        case ERR_INVALID_ARRAY_SIZE: return "Invalid array size";
        case ERR_INVALID_PARAMETER: return "Invalid parameter";
        case ERR_OUT_OF_RANGE: return "Value out of range";
        
        // Calculation
        case ERR_DIVISION_BY_ZERO: return "Division by zero";
        case ERR_OVERFLOW: return "Numeric overflow";
        case ERR_PRECISION_LOSS: return "Precision loss detected";
        case ERR_INVALID_RESULT: return "Invalid calculation result";
        
        // Memory
        case ERR_BUFFER_OVERFLOW: return "Buffer overflow prevented";
        case ERR_MEMORY_ALLOCATION: return "Memory allocation failed";
        case ERR_ARRAY_RESIZE: return "Array resize failed";
        case ERR_MEMORY_LEAK: return "Memory leak detected";
        
        // I/O
        case ERR_FILE_NOT_FOUND: return "File not found";
        case ERR_FILE_READ: return "File read error";
        case ERR_FILE_WRITE: return "File write error";
        case ERR_FILE_CORRUPT: return "File corrupted";
        
        // Rendering
        case ERR_OBJECT_CREATE: return "Object creation failed";
        case ERR_OBJECT_UPDATE: return "Object update failed";
        case ERR_OBJECT_DELETE: return "Object deletion failed";
        case ERR_RACE_CONDITION: return "Race condition detected";
        
        default: return "Unknown error";
    }
}

#endif // ERROR_CODES_MQH
