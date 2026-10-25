# VoiceOver checklist: M1 brief and timeline

Purpose: manual audit that the M1 brief, timeline, deadlines and settings work fully with VoiceOver (PRD M1 acceptance; NFR-A11Y-01). Mark runs it on iPhone, iPad and Mac.

## How to run

1. Turn on VoiceOver. iPhone/iPad: Settings › Accessibility › VoiceOver, or triple-click the side button if the shortcut is set. Mac: Cmd-F5.
2. Gestures. iPhone/iPad: swipe right/left to move to the next/previous element, double-tap to activate, three-finger swipe to scroll. Mac: VO-Right Arrow / VO-Left Arrow to move (VO is Ctrl-Option), VO-Space to activate.
3. Setup. Launch Eagar with full calendar access and calendars that include at least one college (ncad.ie) event and one personal event today, plus one overdue deadline (and one college deadline if possible).
4. Mark each row ✓ or ✗. Put what VoiceOver actually said in Notes for any ✗.

## 1. Today tab

| # | Check | Expected | Pass (✓/✗) | Notes |
|---|---|---|---|---|
| T1 | Navigation title | Reads "Today" as the heading | | |
| T2 | Brief header | Slot name ("Morning brief", "Midday brief" or "End-of-day brief") is a heading, read once before the first section | | |
| T3 | Section headers | Each heading ("Overdue", "Today", "Coming up", "Loans due", "Trials about to bill", "Mail", and so on) is announced as a heading; rotor Headings jumps between them | | |
| T4 | Empty brief | If nothing is due: "Nothing needs you right now." | | |
| T5 | Item title and time | Title then time are read together, e.g. "Due Monday 14:00", "All day", or "09:00 to 10:00"; struck-through state is spoken as the status line (Done, Dismissed) | | |
| T6 | College item | A badge is read as "College, stays on your devices" (one element, no separate icon) | | |
| T7 | Personal item | No college badge is spoken | | |
| T8 | Open button | "Open <title>"; activates and shows the editor or event detail | | |
| T9 | Done button | "Mark <title> done"; afterwards the row says "Done" and the buttons are dimmed/disabled | | |
| T10 | Snooze menu | Button reads "Snooze <title>"; menu offers "In 1 hour" and "Tomorrow at 09:00"; both activate | | |
| T11 | Reschedule button | "Reschedule <title>"; opens sheet with "New due time" picker, Cancel and Save | | |
| T12 | Dismiss button | "Dismiss <title>"; afterwards the row says "Dismissed" | | |
| T13 | Thumbs | "Useful" and "Not useful" buttons; after a tap the chosen one adds the value "Selected" | | |
| T14 | AI summary (needs phrasing on) | Summary text, then "AI summary" and a location badge read as one element | | |
| T15 | Location badge | Reads "Processed: On this device", "On Mac", "Apple PCC", "Meitheal (NCAD)" or "Claude"; each has an icon plus text | | |
| T16 | Hidden items note | If shown: "More not shown: <n>" is read | | |
| T17 | Timeline header | "Timeline" is a heading; if empty, "Nothing on your timeline today." | | |
| T18 | Timeline row | One element: time ("All day" or HH:MM), title, "Deadline" for deadlines, and the college badge text where relevant. The marker dot or flag is not read separately | | |
| T19 | Add deadline | Toolbar button "Add deadline" reachable and opens the editor | | |
| T20 | Calendar access card | If access is not granted: explanation is read and "Allow calendar access" is a button | | |

## 2. Deadlines tab

| # | Check | Expected | Pass (✓/✗) | Notes |
|---|---|---|---|---|
| D1 | Section headers | "Overdue", "Upcoming", "Done" are headings | | |
| D2 | Empty state | "No deadlines", its description and an "Add deadline" button | | |
| D3 | Row | Title, college badge if college, "Due <date and time>", and "Snoozed until ..." if snoozed; hint "Edit deadline" | | |
| D4 | Row activation | Double-tap opens the deadline editor | | |
| D5 | Done button | "Mark <title> done" (open deadlines only; absent on completed ones) | | |
| D6 | More menu | "More actions for <title>"; items: Snooze for 1 hour, Snooze until tomorrow at 09:00, Reschedule, Edit, Delete | | |
| D7 | Swipe equivalents | Swipe Done and Delete are also available as the Done button and the More menu items, with no Actions rotor needed | | |
| D8 | Delete | Delete from the More menu removes the row; focus lands somewhere sensible | | |

## 3. Deadline editor

| # | Check | Expected | Pass (✓/✗) | Notes |
|---|---|---|---|---|
| E1 | Title | "New deadline" or "Edit deadline"; Title field, All day switch, Due date picker all labelled | | |
| E2 | Save | "Save" disabled (dimmed) while the title is empty; Cancel reachable | | |
| E3 | Data class picker | "Data class" segmented control with Personal and College; selected segment is spoken | | |
| E4 | Class footer | Footer explains notification wording for the chosen class | | |
| E5 | Remind me | Each offset ("At the due time", "15 minutes before", ... "1 week before") is a labelled switch | | |
| E6 | Mirror to Reminders | Picker "Mirror to Reminders" with "Don't mirror" and the eligible lists | | |
| E7 | iCloud override | With College selected, switch "Allow iCloud Reminders for this deadline" appears; turning it on shows the dialog "Copy this college deadline to iCloud Reminders?" with "Allow for this deadline" and "Cancel", and the message is read | | |
| E8 | Delete (existing only) | "Delete deadline" then confirmation "Delete this deadline?" with Delete | | |

## 4. Settings

| # | Check | Expected | Pass (✓/✗) | Notes |
|---|---|---|---|---|
| S1 | Kill switch | Switch "Stop all AI" with state On/Off; header "Kill switch"; footer read | | |
| S2 | Calendar rows | Calendar title and account are read; the segmented picker is named "Tag for <calendar>" with Personal / College | | |
| S3 | Proposed label | Unconfirmed tags read "Proposed tag, not yet confirmed" | | |
| S4 | College calendar | College calendars show the badge "College, stays on your devices" | | |
| S5 | Include in brief | "Include in brief" switch on each calendar | | |
| S6 | Reminder lists | Same tag picker, no brief switch | | |
| S7 | Missing NCAD calendar | If shown, the steps are read as one element | | |
| S8 | Brief times | Each slot switch is named by slot; when on, time picker reads "Time for <slot name>" | | |
| S9 | Sections order | "Overdue" reads "Always first". Per section: show switch, "Move <section> up", "Move <section> down", and a "Show up to <n> items" stepper | | |
| S10 | Move buttons | First section's up and last section's down are dimmed; moving changes the order in the Today tab | | |
| S11 | AI phrasing | Inline picker options (Off, On your devices only, Claude for personal items) read with the selected one; footer matches | | |
| S12 | Notifications | "Allow brief and deadline notifications" is a button | | |

## 5. Cross-cutting

| # | Check | Expected | Pass (✓/✗) | Notes |
|---|---|---|---|---|
| X1 | Dynamic Type AX5 | At the largest accessibility size on Today, Deadlines, editor and Settings, no action is truncated or clipped; buttons wrap below the title | | |
| X2 | 44 pt targets | Action buttons, thumbs, More, Done, move arrows and pickers are all comfortable to hit (Accessibility Inspector on Mac) | | |
| X3 | Colour not the only signal | The college badge is a house icon plus the word "College" in an outline; location badges are icon plus text; timeline deadlines use a flag, events a dot. Check with Differentiate Without Color on and Greyscale | | |
| X4 | Reduce Motion | With Reduce Motion on, no motion-dependent cues; nothing relies on animation | | |
| X5 | Keyboard (Mac/iPad) | Tab moves between controls in a sensible order; Space activates buttons; menus open and close with the keyboard; Full Keyboard Access on iPad | | |
| X6 | Focus order | Swiping through Today follows reading order: header, summary, items, actions, timeline | | |
| X7 | Sheets | Editor, Reschedule and event detail sheets announce their titles and can be dismissed with Cancel or Done | | |

## Sign-off

- Device and model:
- OS version:
- Date:
- Tester:
- Result (pass / pass with issues / fail):
- Record every ✗ as an issue titled "VoiceOver M1: <check #>" and link them here:
