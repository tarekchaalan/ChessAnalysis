#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Start the engine thread (safe to call once; subsequent calls are no-ops)
void sf_start(void);

// Stop engine thread and release resources (safe to call once)
void sf_stop(void);

// Send a UCI command line (e.g., "uci", "isready", "position fen ...", "go depth 15")
// Returns false if engine not running or input invalid.
bool sf_send(const char* command);

// Non-blocking: returns next output line if available; otherwise NULL.
// Returned pointer is valid until the next sf_read_line() call.
const char* sf_read_line(void);

#ifdef __cplusplus
}
#endif
