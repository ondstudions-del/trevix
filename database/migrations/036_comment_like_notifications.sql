-- TREVIX · Avisos cuando alguien da me gusta a un comentario.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

ALTER TABLE notifications
    MODIFY type ENUM(
        'follow', 'follow_request', 'follow_accepted', 'like', 'comment_like', 'comment', 'reply', 'mention', 'share',
        'community', 'community_request', 'community_accepted', 'system',
        'song_approved', 'song_rejected', 'song_removed',
        'story_mention', 'event_going', 'featured',
        'warning', 'verification_approved', 'verification_rejected',
        'appeal_accepted', 'appeal_rejected',
        'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected',
        'wallet_adjusted', 'collaborator_enabled',
        'gift', 'new_post', 'new_note', 'new_story',
        'ad_approved', 'ad_rejected', 'ad_finished'
    ) NOT NULL;
