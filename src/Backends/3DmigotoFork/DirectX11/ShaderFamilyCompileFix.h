#pragma once

#include "Overlay.h"

// IniWarning is private to IniHandler.cpp in upstream. Keep the family engine
// in its own translation unit while preserving the same overlay severity.
#define IniWarning(...) LogOverlay(LOG_WARNING, __VA_ARGS__)

