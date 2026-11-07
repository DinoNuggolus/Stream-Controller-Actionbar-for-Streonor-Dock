local addonName, ns = ...
-- SKELETON ONLY. TODO(part 2): collect allowlisted ordinary data, guard every field BEFORE
-- calling Core, resolve metadata only if slot identity still matches, and refresh snapshot
-- on assignment/page/login/logout plus relevant value events. Never retain stale readings.
-- Convert item cooldown times from the game clock to server seconds for exported endsAt.
-- No spell cooldown collection. Snapshot must always be labeled "saved snapshot".
ns.Export = {}
