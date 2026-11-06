import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { Store } from "../server/store";

test("browser identities, friends, and offline chat survive closing and reopening the database", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "gambit-store-")),
    file = path.join(dir, "test.sqlite");
  let store: Store | undefined;
  try {
    store = new Store(file);
    const a = store.create(),
      b = store.create();
    store.addFriend(a.user.id, b.user.id);
    store.message(a.user.id, b.user.id, "See you tomorrow.");
    store.db.close();
    store = new Store(file);
    assert.equal(store.auth(a.token)?.id, a.user.id);
    assert.equal(store.friends(a.user.id)[0].id, b.user.id);
    assert.equal(store.unread(b.user.id, a.user.id), 1);
    assert.equal(
      store.history(b.user.id, a.user.id)[0].text,
      "See you tomorrow.",
    );
    assert.equal(store.unread(b.user.id, a.user.id), 0);
  } finally {
    store?.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
