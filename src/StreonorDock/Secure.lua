local addonName, ns = ...
-- SKELETON ONLY. TODO(part 2): capability-validated secure buttons and temporary overrides.
-- Match ActionButtonUseKeyDown, clear stale attributes, and separate right-click clearing.
-- No SetBinding/SaveBindings fallback; no secure snippets. Never bind during combat.
ns.Secure = {}
