-- The display filename belongs to the message that carries the bytes, not to
-- whoever uploaded them first. `attachments.filename` stays as the fallback for
-- every message sent before this migration, and for a link whose author has no
-- recorded name for those bytes (a forward, a bot, an emoji import).
-- `attachment_uploaders.filename` remembers what each uploader called the bytes,
-- which is how a send finds the name its author chose without a wire change.
ALTER TABLE attachment_uploaders ADD COLUMN filename TEXT;
ALTER TABLE message_attachments ADD COLUMN filename TEXT;
