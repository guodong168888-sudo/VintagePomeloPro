#include "text_input.h"

#include "include/text-input-unstable-v3-server-protocol.h"

#include <algorithm>
#include <vector>

#undef LOG_TAG
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000
#define LOG_TAG "WL_TextInput"
#include <hilog/log.h>

TextInputManager* TextInputManager::GetInstance() {
    static TextInputManager s;
    return &s;
}

void TextInputManager::Register(wl_display* display) {
    if (global_) return;
    display_ = display;
    global_ = wl_global_create(display, &zwp_text_input_manager_v3_interface, 1,
                               this, manager_bind);
    OH_LOG_INFO(LOG_APP, "[TextInput] manager registered armed=%{public}d",
                armed_ ? 1 : 0);
}

static const struct zwp_text_input_manager_v3_interface kManagerImpl = {
    .destroy = TextInputManager::manager_destroy,
    .get_text_input = TextInputManager::manager_get_text_input,
};

static const struct zwp_text_input_v3_interface kTextInputImpl = {
    .destroy = TextInputManager::ti_destroy,
    .enable = TextInputManager::ti_enable,
    .disable = TextInputManager::ti_disable,
    .set_surrounding_text = TextInputManager::ti_set_surrounding_text,
    .set_text_change_cause = TextInputManager::ti_set_text_change_cause,
    .set_content_type = TextInputManager::ti_set_content_type,
    .set_cursor_rectangle = TextInputManager::ti_set_cursor_rectangle,
    .commit = TextInputManager::ti_commit,
};

void TextInputManager::manager_bind(wl_client* client, void* data,
                                    uint32_t version, uint32_t id) {
    wl_resource* res = wl_resource_create(client, &zwp_text_input_manager_v3_interface,
                                          std::min(version, 1u), id);
    wl_resource_set_implementation(res, &kManagerImpl, data, nullptr);
}

void TextInputManager::manager_destroy(wl_client*, wl_resource* r) {
    wl_resource_destroy(r);
}

void TextInputManager::manager_get_text_input(wl_client*, wl_resource* manager,
                                              uint32_t id, wl_resource*) {
    auto* self = GetInstance();
    wl_client* client = wl_resource_get_client(manager);
    wl_resource* res = wl_resource_create(client, &zwp_text_input_v3_interface, 1, id);
    wl_resource_set_implementation(res, &kTextInputImpl, nullptr, resource_destroyed);

    wl_resource* enterSurface = nullptr;
    {
        std::lock_guard<std::mutex> lock(self->mutex_);
        self->entries_.push_back({});
        self->entries_.back().res = res;
        // 输入对象晚于键盘焦点创建时立即补发 enter, 不丢协议激活。
        if (self->armed_ && self->focusedSurface_ &&
            wl_resource_get_client(res) == wl_resource_get_client(self->focusedSurface_)) {
            self->entries_.back().enteredSurface = self->focusedSurface_;
            enterSurface = self->focusedSurface_;
        }
    }
    OH_LOG_INFO(LOG_APP, "[TextInput] object created client=%{public}p res=%{public}p entries=%{public}d pendingEnter=%{public}d",
                client, res, (int)self->entries_.size(), enterSurface ? 1 : 0);
    if (enterSurface) zwp_text_input_v3_send_enter(res, enterSurface);
}

void TextInputManager::resource_destroyed(wl_resource* r) {
    auto* self = GetInstance();
    std::lock_guard<std::mutex> lock(self->mutex_);
    self->entries_.erase(std::remove_if(self->entries_.begin(), self->entries_.end(),
        [&](const Entry& entry) { return entry.res == r; }), self->entries_.end());
    OH_LOG_INFO(LOG_APP, "[TextInput] object destroyed res=%{public}p entries=%{public}d",
                r, (int)self->entries_.size());
}

void TextInputManager::ti_destroy(wl_client*, wl_resource* r) {
    wl_resource_destroy(r);
}

void TextInputManager::ti_enable(wl_client*, wl_resource* r) {
    auto* self = GetInstance();
    wl_resource* entered = nullptr;
    {
        std::lock_guard<std::mutex> lock(self->mutex_);
        for (Entry& entry : self->entries_) {
            if (entry.res != r) continue;
            entry.enabled = true;
            entered = entry.enteredSurface;
            break;
        }
    }
    OH_LOG_INFO(LOG_APP, "[TextInput] enable res=%{public}p surface=%{public}p client=%{public}p",
                r, entered, wl_resource_get_client(r));
}

void TextInputManager::ti_disable(wl_client*, wl_resource* r) {
    auto* self = GetInstance();
    {
        std::lock_guard<std::mutex> lock(self->mutex_);
        for (Entry& entry : self->entries_) {
            if (entry.res != r) continue;
            entry.enabled = false;
            break;
        }
    }
    OH_LOG_INFO(LOG_APP, "[TextInput] disable res=%{public}p client=%{public}p",
                r, wl_resource_get_client(r));
}

void TextInputManager::ti_set_surrounding_text(wl_client*, wl_resource*,
                                               const char*, int32_t, int32_t) {}
void TextInputManager::ti_set_text_change_cause(wl_client*, wl_resource*, uint32_t) {}
void TextInputManager::ti_set_content_type(wl_client*, wl_resource*, uint32_t, uint32_t) {}
void TextInputManager::ti_set_cursor_rectangle(wl_client*, wl_resource*,
                                               int32_t, int32_t, int32_t, int32_t) {}

void TextInputManager::ti_commit(wl_client*, wl_resource* r) {
    auto* self = GetInstance();
    std::lock_guard<std::mutex> lock(self->mutex_);
    for (Entry& entry : self->entries_) {
        if (entry.res == r) {
            entry.commitCount++;
            break;
        }
    }
}

void TextInputManager::OnKeyboardEnter(uint32_t toplevelId, wl_resource* surface) {
    if (!surface) return;

    struct SendAction {
        bool enter;
        wl_resource* res;
        wl_resource* surface;
    };
    std::vector<SendAction> actions;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (focusedSurface_ == surface) {
            OH_LOG_INFO(LOG_APP, "[TextInput] focus enter dup tl=%{public}u surface=%{public}p",
                        toplevelId, surface);
            return;
        }
        focusedToplevel_ = toplevelId;
        focusedSurface_ = surface;
        wl_client* client = wl_resource_get_client(surface);

        // 先把已经 enter 到其他 surface 的对象 leave 掉 (同 client 也要重进)。
        for (Entry& entry : entries_) {
            if (entry.enteredSurface && entry.enteredSurface != surface) {
                actions.push_back({false, entry.res, entry.enteredSurface});
                entry.enteredSurface = nullptr;
                entry.enabled = false;
            }
        }
        if (armed_) {
            for (Entry& entry : entries_) {
                if (!entry.res || wl_resource_get_client(entry.res) != client) continue;
                if (entry.enteredSurface == surface) continue;
                entry.enteredSurface = surface;
                actions.push_back({true, entry.res, surface});
            }
        }
    }

    for (const SendAction& action : actions) {
        if (action.enter) {
            OH_LOG_INFO(LOG_APP, "[TextInput] send enter res=%{public}p surface=%{public}p surfClient=%{public}p",
                        action.res, action.surface, wl_resource_get_client(action.surface));
            zwp_text_input_v3_send_enter(action.res, action.surface);
        } else {
            OH_LOG_INFO(LOG_APP, "[TextInput] send leave res=%{public}p surface=%{public}p",
                        action.res, action.surface);
            zwp_text_input_v3_send_leave(action.res, action.surface);
        }
    }
    OH_LOG_INFO(LOG_APP, "[TextInput] focus enter tl=%{public}u surface=%{public}p armed=%{public}d actions=%{public}d",
                toplevelId, surface, armed_ ? 1 : 0, (int)actions.size());
}

void TextInputManager::OnKeyboardLeave() {
    struct SendAction {
        wl_resource* res;
        wl_resource* surface;
    };
    std::vector<SendAction> actions;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        focusedToplevel_ = 0;
        focusedSurface_ = nullptr;
        for (Entry& entry : entries_) {
            if (!entry.enteredSurface) continue;
            actions.push_back({entry.res, entry.enteredSurface});
            entry.enteredSurface = nullptr;
            entry.enabled = false;
        }
    }
    for (const SendAction& action : actions) {
        OH_LOG_INFO(LOG_APP, "[TextInput] send leave res=%{public}p surface=%{public}p",
                    action.res, action.surface);
        zwp_text_input_v3_send_leave(action.res, action.surface);
    }
    if (!actions.empty()) {
        OH_LOG_INFO(LOG_APP, "[TextInput] focus leave actions=%{public}d", (int)actions.size());
    }
}

void TextInputManager::OnSurfaceDestroyed(wl_resource* surface) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (focusedSurface_ == surface) {
        OH_LOG_INFO(LOG_APP, "[TextInput] focus surface destroyed surface=%{public}p tl=%{public}u",
                    surface, focusedToplevel_);
        focusedSurface_ = nullptr;
        focusedToplevel_ = 0;
    }
    for (Entry& entry : entries_) {
        if (entry.enteredSurface == surface) {
            entry.enteredSurface = nullptr;
            entry.enabled = false;
        }
    }
}

bool TextInputManager::IsEnabled() const {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const Entry& entry : entries_) {
        if (entry.enabled && entry.enteredSurface) return true;
    }
    return false;
}
