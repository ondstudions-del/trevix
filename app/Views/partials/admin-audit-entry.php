<?php
/**
 * Entrada del registro de auditoría.
 *
 * @var array $entry  fila de AuditLog::latest() o AuditLog::forTarget()
 * @var bool  $full   muestra el objetivo y la IP
 */
$full = $full ?? false;
$details = $entry['details'];
$isSong = ($entry['target_type'] ?? '') === 'song';
$subject = $isSong
    ? (isset($details['title'])
        ? (isset($details['artist'])
            ? t('«{title}» de @{artist}', ['title' => $details['title'], 'artist' => $details['artist']])
            : '«' . $details['title'] . '»')
        : null)
    : ($details['username'] ?? $details['author'] ?? $details['name'] ?? null);
$note = $details['note'] ?? null;
$targetUrl = null;
if ($full && !empty($entry['target_type']) && !empty($entry['target_id'])) {
    $targetUrl = match ($entry['target_type']) {
        'user'  => url('admin/users.php', ['id' => (int) $entry['target_id']]),
        'post', 'comment', 'message', 'community', 'story' => url('admin/reports.php', ['type' => $entry['target_type'], 'id' => (int) $entry['target_id']]),
        'song'  => url('admin/music.php', ['q' => isset($details['artist']) ? '@' . $details['artist'] : null]),
        default => null,
    };
}
$extra = [];
if (isset($details['from'], $details['to'])) {
    $roles = ($entry['action'] ?? '') === 'user.role' ? \Trevix\Models\User::ROLE_LABELS : [];
    $extra[] = (isset($roles[$details['from']]) ? t($roles[$details['from']]) : $details['from'])
        . ' → ' . (isset($roles[$details['to']]) ? t($roles[$details['to']]) : $details['to']);
}
if (!empty($details['days'])) {
    $extra[] = $details['days'] . ' ' . plural((int) $details['days'], 'día', 'días');
} elseif (($entry['action'] ?? '') === 'user.suspend') {
    $extra[] = t('sin fecha de fin');
}
if (!empty($details['fields'])) {
    $extra[] = t('Cambió: {fields}', ['fields' => implode(', ', array_map('t', explode(', ', (string) $details['fields'])))]);
}
if (!empty($details['appeal'])) {
    $extra[] = t('Apelación #{id}', ['id' => $details['appeal']]);
}
if (!empty($details['reports'])) {
    $extra[] = $details['reports'] . ' ' . plural((int) $details['reports'], 'reporte cerrado', 'reportes cerrados');
}
if (($entry['action'] ?? '') === 'settings.update') {
    foreach (array_filter($details, 'is_array') as $key => $change) {
        $extra[] = \Trevix\Models\AppSetting::describeChange((string) $key, $change);
    }
}
$label = t($entry['label']);
?>
<li class="audit-entry">
    <span class="audit-entry__dot" aria-hidden="true"></span>
    <div class="audit-entry__body">
        <p>
            <strong>@<?= e($entry['admin_username'] ?? t('cuenta eliminada')) ?></strong>
            <?= e(mb_strtolower(mb_substr($label, 0, 1)) . mb_substr($label, 1)) ?>
            <?php if ($subject !== null): ?>
                <span class="audit-entry__subject"><?= e(($entry['target_type'] ?? '') === 'community' || $isSong ? $subject : '@' . $subject) ?></span>
            <?php endif; ?>
        </p>
        <?php if ($extra !== [] || $note !== null): ?>
            <p class="audit-entry__note">
                <?= e(implode(' · ', $extra)) ?><?= $extra !== [] && $note !== null ? ' · ' : '' ?><?= $note !== null ? '«' . e($note) . '»' : '' ?>
            </p>
        <?php endif; ?>
        <p class="audit-entry__meta">
            <?= time_tag((string) $entry['created_at']) ?>
            <?php if ($full && !empty($entry['ip'])): ?> · IP <?= e($entry['ip']) ?><?php endif; ?>
            <?php if ($targetUrl !== null): ?> · <a href="<?= e($targetUrl) ?>"><?= e(t('Ver objetivo')) ?></a><?php endif; ?>
        </p>
    </div>
</li>
