#ifndef CONTROLLER_SWITCH_H
#define CONTROLLER_SWITCH_H

#include "controller_api.h"

// Split screen on the Switch stops at two players for now
#define SWITCH_MAX_LOCAL_PLAYERS 2

extern struct ControllerAPI controller_switch;

void show_swkb(char *text);
void hide_swkb(void);
void poll_swkb(void);
int controller_switch_connected_pad_count(void);

#endif
