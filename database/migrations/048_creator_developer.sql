ALTER TABLE users
    MODIFY COLUMN creator_category ENUM(
        'music_artist',
        'influencer',
        'blogger',
        'developer',
        'other'
    ) NULL;
