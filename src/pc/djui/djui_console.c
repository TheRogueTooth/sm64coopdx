#include <stdio.h>
#include <string.h>
#include "djui.h"
#include "djui_console.h"
#include "engine/math_util.h"
#include "pc/game_main.h"
#include "pc/string_utils.h"
#include "pc/fs/fs.h"

#define MAX_CONSOLE_MESSAGES 500

struct DjuiConsole* gDjuiConsole = NULL;
bool gDjuiConsoleFocus = false;
char gDjuiConsoleTmpBuffer[CONSOLE_MAX_TMP_BUFFER] = "";
u32 sDjuiConsoleMessages = 0;
bool sDjuiConsoleQueueMessages = true;

struct ConsoleQueuedMessage {
    char* message;
    enum ConsoleMessageLevel level;
    struct ConsoleQueuedMessage* next;
};

struct ConsoleQueuedMessage* sConsoleQueuedMessages = NULL;

static void djui_console_message_queue(const char* message, enum ConsoleMessageLevel level) {
    struct ConsoleQueuedMessage* queued = malloc(sizeof(struct ConsoleQueuedMessage));
    queued->message = strdup(message);
    queued->level = level;
    queued->next = NULL;
    if (sConsoleQueuedMessages == NULL) {
        sConsoleQueuedMessages = queued;
        return;
    }

    struct ConsoleQueuedMessage* entry = sConsoleQueuedMessages;
    while (entry->next) { entry = entry->next; }
    entry->next = queued;
}

void djui_console_message_dequeue(void) {
    if (!gDjuiConsole) { return; }
    sDjuiConsoleQueueMessages = false;
    struct ConsoleQueuedMessage* entry = sConsoleQueuedMessages;
    while (entry) {
        struct ConsoleQueuedMessage* next = entry->next;
        djui_console_message_create(entry->message, entry->level);
        free(entry->message);
        free(entry);
        entry = next;
    }
    sConsoleQueuedMessages = NULL;
}

bool djui_console_render(struct DjuiBase* base) {
    struct DjuiConsole* console = (struct DjuiConsole*)base;
    djui_base_set_size(base, gDjuiRoot->base.width.value, gDjuiRoot->base.height.value * 0.5f);
    if (console->scrolling) {
        f32 yMax = console->base.comp.height - console->flow->base.height.value;
        f32 target = console->flow->base.y.value + (console->scrollY - console->flow->base.y.value) * (configSmoothScrolling ? 0.5f : 1.f);

        console->flow->base.y.value = clamp(target, yMax, 0.f);
        if (target < yMax || 0.f < target) {
            console->scrollY = clamp(target, yMax, 0.f);
            if (target > 0.f) { gDjuiConsole->scrolling = false; }
        }
    } else { console->scrollY = console->flow->base.y.value; }

    djui_rect_render(base);
    return true;
}

static void djui_console_destroy(struct DjuiBase* base) {
    struct DjuiConsole* console = (struct DjuiConsole*)base;
    free(console);
}

void djui_console_toggle(void) {
    if (gDjuiConsole == NULL) { return; }
    gDjuiConsoleFocus = !gDjuiConsoleFocus;
    djui_base_set_visible(&gDjuiConsole->base, gDjuiConsoleFocus);

    if (gDjuiConsoleFocus) {
        if (gDjuiChatBoxFocus) { djui_chat_box_toggle(); }
        djui_interactable_set_input_focus(&gDjuiConsole->base);
    } else {
        djui_interactable_set_input_focus(NULL);
    }
}

static void djui_console_on_scroll(UNUSED struct DjuiBase *base, UNUSED float x, float y) {
    if (gDjuiConsole == NULL) { return; }

    f32 yMax = gDjuiConsole->base.comp.height - gDjuiConsole->flow->base.height.value;

    y *= 24.f;
    if (gDjuiInputHeldControl) { y /= 2; }
    if (gDjuiInputHeldShift) { y *= 3; }

    gDjuiConsole->scrollY -= y;
    
    if (!gDjuiConsole->scrolling) {
        gDjuiConsole->scrolling = y > 0 && gDjuiConsole->scrollY > yMax;
    }
}

static bool djui_console_on_key_down(UNUSED struct DjuiBase* base, int scancode) {
    if (gDjuiConsole == NULL) { return false; }
    f32 yMax = gDjuiConsole->base.comp.height - gDjuiConsole->flow->base.height.value;

    f32 pageAmount = gDjuiConsole->base.comp.height * 3.0f / 4.0f;

    switch (scancode) {
        case SCANCODE_UP:
            gDjuiConsole->scrollY -= 15;
            break;
        case SCANCODE_DOWN:
            gDjuiConsole->scrollY += 15;
            break;
        case SCANCODE_PAGE_UP:
            gDjuiConsole->scrollY -= pageAmount;
            break;
        case SCANCODE_PAGE_DOWN:
            gDjuiConsole->scrollY += pageAmount;
            break;
        case SCANCODE_ESCAPE: djui_console_toggle(); break;
        default: break;
    }

    if (!gDjuiConsole->scrolling) {
        gDjuiConsole->scrolling = gDjuiConsole->scrollY < 0 && gDjuiConsole->scrollY > yMax;
    }
    return true;
}

// There's no way to read the console on the Switch, so keep a copy next to the save data.
// PC test runs read the same file
#define CONSOLE_LOG_MAX_SIZE (1024 * 1024)
#define CONSOLE_SEEN_SLOTS 2048
#define CONSOLE_SEEN_PROBES 8
#define CONSOLE_MAX_REPEATS 4

// A script erroring every frame must not get to spend the frame here, so each exact
// message only gets through a few times
static bool djui_console_should_show(const char* message) {
    static u32 sHashes[CONSOLE_SEEN_SLOTS] = { 0 };
    static u8 sCounts[CONSOLE_SEEN_SLOTS] = { 0 };

    u32 hash = 5381;
    for (const char* c = message; *c != '\0'; c++) { hash = hash * 33 + (u8)*c; }
    if (hash == 0) { hash = 1; }

    for (u32 probe = 0; probe < CONSOLE_SEEN_PROBES; probe++) {
        u32 slot = (hash + probe) % CONSOLE_SEEN_SLOTS;
        if (sHashes[slot] == 0) {
            sHashes[slot] = hash;
            sCounts[slot] = 1;
            return true;
        }
        if (sHashes[slot] == hash) {
            if (sCounts[slot] >= CONSOLE_MAX_REPEATS) { return false; }
            sCounts[slot]++;
            return true;
        }
    }
    return true;
}

static void djui_console_log_to_sd(const char* message, enum ConsoleMessageLevel level) {
    static bool sStarted = false;
    static size_t sWritten = 0;
    if (sWritten > CONSOLE_LOG_MAX_SIZE) { return; }

    // Keep the previous session's log, a crash is usually found out about after relaunching
    if (!sStarted) {
        char previous[SYS_MAX_PATH] = { 0 };
        snprintf(previous, SYS_MAX_PATH, "%s", fs_get_write_path("couch-log-previous.txt"));
        remove(previous);
        rename(fs_get_write_path("couch-log.txt"), previous);
    }

    FILE* f = fopen(fs_get_write_path("couch-log.txt"), sStarted ? "a" : "w");
    if (!f) { return; }
    sStarted = true;
    sWritten += fprintf(f, "[%d] %s\n", (int)level, message);
    fclose(f);
}

void djui_console_message_create(const char* message, enum ConsoleMessageLevel level) {
    if (!djui_console_should_show(message)) { return; }
    djui_console_log_to_sd(message, level);
#ifdef __SWITCH__
    // A script erroring every frame fills this quickly, and freeing the oldest message has
    // crashed here on the Switch. Nothing can read it on this platform, so just stop adding
    if (sDjuiConsoleMessages >= MAX_CONSOLE_MESSAGES - 1) { return; }
#endif
    if (sDjuiConsoleQueueMessages || !gDjuiConsole) {
        djui_console_message_queue(message, level);
        return;
    }
    djui_base_compute_tree(&gDjuiConsole->base);

    struct DjuiBase* cfBase = &gDjuiConsole->flow->base;

    f32 maxTextWidth = gDjuiConsole->base.comp.width - gDjuiConsole->base.padding.left.value - gDjuiConsole->base.padding.right.value;

    struct DjuiText* text = djui_text_create(cfBase, message);
    struct DjuiBase* tBase = &text->base;
    djui_base_set_alignment(tBase, DJUI_HALIGN_LEFT, DJUI_VALIGN_BOTTOM);
    djui_base_set_size_type(tBase, DJUI_SVT_ABSOLUTE, DJUI_SVT_ABSOLUTE);
    djui_base_set_size(tBase, maxTextWidth, 32);
    switch (level) {
        case CONSOLE_MESSAGE_INFO:
            djui_base_set_color(tBase, 220, 220, 220, 255);
            break;
        case CONSOLE_MESSAGE_WARNING:
            djui_base_set_color(tBase, 255, 255, 160, 255);
            break;
        case CONSOLE_MESSAGE_ERROR:
            djui_base_set_color(tBase, 255, 160, 160, 255);
            break;
    }

    // figure out chat message height
    text->base.comp.width = maxTextWidth;
    f32 messageHeight = djui_text_count_lines(text, 10) * (text->font->lineHeight * text->font->defaultFontScale) + 8;
    djui_base_set_size(tBase, maxTextWidth, messageHeight);

    f32 heightAdjust = messageHeight + gDjuiConsole->flow->margin.value;
    cfBase->height.value += heightAdjust;

    if (gDjuiConsole->scrolling && gDjuiConsole->scrollY != 0) {
        cfBase->y.value -= heightAdjust;
        gDjuiConsole->scrollY -= heightAdjust;
    }

    sDjuiConsoleMessages++;
    if (sDjuiConsoleMessages >= MAX_CONSOLE_MESSAGES) {
        if (cfBase->child) {
            heightAdjust = cfBase->child->base->height.value + gDjuiConsole->flow->margin.value;
            cfBase->height.value -= heightAdjust;
            if (gDjuiConsole->scrolling && gDjuiConsole->scrollY != 0) {
                cfBase->y.value += heightAdjust;
                gDjuiConsole->scrollY += heightAdjust;
            }
        }

        djui_base_destroy_one_child(cfBase);
        sDjuiConsoleMessages--;
    }
}

struct DjuiConsole* djui_console_create(void) {
    if (gDjuiConsole != NULL) {
        djui_base_destroy(&gDjuiConsole->base);
        gDjuiConsole = NULL;
    }

    struct DjuiConsole* console = calloc(1, sizeof(struct DjuiConsole));
    struct DjuiBase* base = &console->base;

    djui_base_init(NULL, base, djui_console_render, djui_console_destroy);
    djui_base_set_size_type(base, DJUI_SVT_ABSOLUTE, DJUI_SVT_ABSOLUTE);
    djui_base_set_size(base, gDjuiRoot->base.width.value, gDjuiRoot->base.height.value * 0.5f);
    djui_base_set_alignment(base, DJUI_HALIGN_LEFT, DJUI_VALIGN_TOP);
    djui_base_set_color(base, 0, 0, 0, 200);
    djui_base_set_padding(base, 0, 8, 8, 8);
    djui_base_set_visible(base, false);

    djui_interactable_create(base, NULL);
    djui_interactable_hook_key(base, djui_console_on_key_down, NULL);
    djui_interactable_hook_scroll(base, djui_console_on_scroll);

    struct DjuiFlowLayout* flow = djui_flow_layout_create(base);
    struct DjuiBase* cfBase = &flow->base;
    djui_base_set_alignment(cfBase, DJUI_HALIGN_LEFT, DJUI_VALIGN_BOTTOM);
    djui_base_set_location(cfBase, 0, 0);
    djui_base_set_size_type(cfBase, DJUI_SVT_RELATIVE, DJUI_SVT_ABSOLUTE);
    djui_base_set_size(cfBase, 1.0f, 0);
    djui_base_set_color(cfBase, 0, 0, 0, 0);
    djui_base_set_padding(cfBase, 2, 2, 2, 2);
    djui_flow_layout_set_margin(flow, 2);
    djui_flow_layout_set_flow_direction(flow, DJUI_FLOW_DIR_UP);
    cfBase->addChildrenToHead = true;
    cfBase->abandonAfterChildRenderFail = true;
    console->flow = flow;

    gDjuiConsole = console;

    return console;
}
