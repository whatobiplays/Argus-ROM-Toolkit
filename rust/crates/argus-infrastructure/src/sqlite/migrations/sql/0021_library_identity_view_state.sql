ALTER TABLE library_view_state
ADD COLUMN identity_membership_revision INTEGER NOT NULL DEFAULT 1
    CHECK (identity_membership_revision >= 1);
