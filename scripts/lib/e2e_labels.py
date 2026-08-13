# SPDX-License-Identifier: Apache-2.0
"""The accessible names this harness drives the app by.

Kept in one place because they are a contract with the UI, not incidental
strings: when a label changes, exactly one line here changes with it, and a
scenario that no longer matches says so rather than timing out on a name
nobody remembered was duplicated across three files.
"""

# Not the hint text: it vanishes once typed, and goes bare for a thread/DM, once colliding with "Pinned/Search messages".
COMPOSER = "Message composer"
SEND = "Send message"
ATTACH = "Attach a file"
ADD_REACTION = "Add a reaction"
REMOVE_ATTACHMENT = "Remove attachment"

# Rail and navigation
SPACE_MENU = "Space menu"
SPACE_SETTINGS = "Space settings"
PERSONAL_SETTINGS = "Personal settings"

# Personal settings. Nav entries first: a control needs its own pane selected.
ACCOUNT_PANE = "Account & presence"
APPEARANCE_PANE = "Appearance"
CHANGE_AVATAR = "Change profile picture"
CROP_TITLE = "Crop your picture"
USE_PICTURE = "Use picture"
THEME = "Theme"
STATUS = "Status"

# Space settings
WHO_CAN_JOIN = "Who can join"
# The embedded pane's own row: distinct from the nav row above by its
# "currently <policy>" suffix, which is what makes the second click land.
WHO_CAN_JOIN_ROW = "Who can join, currently"
JOIN_OPEN = "Anyone with the address"
JOIN_INVITE = "People with an invite"
ROLES = "Roles"
NEW_ROLE = "New role"
ROLE_NAME = "Role name"
CREATE_ROLE = "Create role"

# Voice
IN_CALL = "in call"
SHARE_SCREEN = "Share a screen"
SHARING_NOTICE = "You are sharing your screen"
STOP_SHARING = "Stop sharing"
MUTE = "Mute"
UNMUTE = "Unmute"
LEAVE_CALL = "Leave call"

# Calling in a DM
START_DM = "Message"
DM_CALL = "Call"
DM_CALL_BACK = "Back to messages"

# Replies: only the rendered quote is reachable here, never "Reply" itself (see e2e_replies.py).
REPLY_UNAVAILABLE = "Message unavailable"
REPLY_UNAVAILABLE_QUOTE = "Reply to a message that is not available"
JUMP_FAILED = "Could not find that message."

# Threads: the reply-count affordance and the back tooltip, never the bar's own title (see e2e_threads.py).
THREAD_HEADER = "Back to the conversation"

# Canvas
OPEN_CANVAS = "Open canvas"
CLOSE_CANVAS = "Close canvas"
PEN_TOOL = "Pen"
NOTE_TOOL = "Note"
SHAPE_TOOL = "Shape"
ERASER_TOOL = "Eraser"
SELECT_TOOL = "Move"
UNDO = "Undo"
MORE_CANVAS_ACTIONS = "More canvas actions"
SHOW_ACTIVITY_LOG = "Show activity log"
HIDE_ACTIVITY_LOG = "Hide activity log"
CLEAR_CANVAS = "Clear canvas"
BRING_TO_FRONT = "Bring to front"
SEND_TO_BACK = "Send to back"
NOTE_TEXT_FIELD = "What do you want to remember?"
ADD_NOTE = "Add note"

# The fixture channels the seed creates
TEXT_CHANNEL = "general"
VOICE_CHANNEL = "lounge"

# Messages the run sends, referred to again when reacting to or reporting them
FIRST_MESSAGE = "first message from alice"
REPLY_MESSAGE = "and a reply from bob"
