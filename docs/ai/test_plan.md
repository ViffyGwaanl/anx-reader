# AI Panel / Sync / Backup — Test Plan

## Devices / Platforms

- iPadOS (>=600 width, e.g. iPad 11")
- iOS iPhone (<600 width)
- Android tablet/phone
- Desktop (optional)

## PR-1 Dock Resize

- [ ] Drag divider adjusts width/height smoothly
- [ ] 16px hit target works with finger
- [ ] Width/height persists after leaving/returning reading page
- [ ] Clamp works (min/max)

## PR-2 Bottom Sheet Resizable

- [ ] Drag handle changes height
- [ ] Snap points: 0.35/0.6/0.9/0.95
- [ ] Reopen remembers last size

## PR-3 iPad Panel Mode + Dock Side

- [ ] dock-right default unchanged
- [ ] dock-left order correct
- [ ] dock-left disables drawer edge swipe
- [ ] TOC button still opens drawer
- [ ] iPad bottomSheet mode forces modal sheet

## PR-4 Font Scale

- [ ] Slider updates markdown + input
- [ ] Persisted between opens
- [ ] Reset returns to 1.0

## PR-5 Quick Prompts Config

- [ ] Defaults shown when no custom list
- [ ] Custom list shows enabled chips only
- [ ] Editor supports add/edit/delete/reorder
- [ ] Reset clears custom list
- [ ] User prompt editor maxLength = 20000

## PR-6 WebDAV AI settings sync

- [ ] Upload/download ai_settings.json
- [ ] Does not sync api_key
- [ ] Conflict resolution uses updatedAt

## PR-7 Backup/Restore enhancements

- [ ] Export/import via Files works on iOS
- [ ] Clear warning about overwrite
- [ ] Optional encrypted api_key flow
- [ ] Rollback on failure

