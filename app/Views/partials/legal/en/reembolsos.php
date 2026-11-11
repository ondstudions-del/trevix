<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$support = '<a href="' . e(url('profile.php', ['u' => (string) \Trevix\Core\Config::get('app.ix.username', 'soport')])) . '">@' . e((string) \Trevix\Core\Config::get('app.ix.username', 'soport')) . '</a>';
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
?>
<p>This policy explains when and how we refund money from the TREVIX wallet: top-ups, subscriptions to collaborators,
    gifts and earnings withdrawals. It complements the
    <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>">Terms and Conditions</a>. All amounts are in US dollars
    (USD).</p>

<h2>1. Wallet top-ups</h2>
<ul>
    <li><strong>Top-ups under review.</strong> While the team hasn't reviewed a top-up, you can cancel it from Wallet. If
        you cancel it or we reject it (for example, because the receipt doesn't match a payment we received) and the money
        did reach our account, we return it through the same payment method once you write to us with the
        reference.</li>
    <li><strong>Unused balance: 30 days.</strong> You can ask for a refund of topped-up balance you haven't spent if you
        request it within 30 days of the top-up. It is returned through the same payment method you used and for the
        amount that was credited. If you already spent part of it, the rest of that top-up is returned.</li>
    <li>After 30 days, the balance stays available to use within TREVIX, but it is no longer refundable.</li>
    <li>Topped-up money can't be withdrawn as earnings: only what you earn as a collaborator and from gifts can be withdrawn.</li>
</ul>

<h2>2. Subscriptions to collaborators</h2>
<p>When you subscribe, you get immediate access to the collaborator's exclusive content. That's why subscriptions are
    <strong>non-refundable</strong>: not for unused days, if you unfollow the collaborator or if they pause their plan
    (you keep access until the expiry date). Refunds only apply in these cases:</p>
<ul>
    <li><strong>Duplicate charge:</strong> the same purchase was charged twice because of an error.</li>
    <li><strong>TREVIX technical error:</strong> you were charged a different amount than the one shown, or a platform
        failure kept you from seeing the content you paid for.</li>
    <li><strong>Collaborator account removed:</strong> if the team deletes or suspends the collaborator's account for
        breaking the rules, we refund the share of access days you had left.</li>
</ul>
<p>These refunds always go <strong>to your TREVIX wallet</strong>, not to an external payment method. You must report a
    duplicate charge or error within 30 days of the charge. When we refund a purchase, we may deduct what the
    collaborator received for it from their wallet.</p>

<h2>3. Gifts</h2>
<ul>
    <li>Gifts are paid with your wallet balance. You can send them when you buy them or keep them in "My gifts" to send
        later; each stored gift keeps the price you paid.</li>
    <li>Gifts are <strong>non-refundable</strong> once sent, because the amount is credited right away to the person who
        receives it. Stored gifts you haven't sent can't be turned back into balance either.</li>
    <li>The recipient gets the gift's price minus the TREVIX commission shown in the gift shop. That amount can be
        withdrawn as earnings.</li>
    <li>Refunds, to your wallet, only apply to a duplicate charge or a TREVIX technical error reported within 30 days.
        In that case we may deduct what was credited from the recipient's wallet.</li>
</ul>

<h2>4. Earnings withdrawals</h2>
<ul>
    <li>When you request a withdrawal, the amount is deducted from your balance and goes under review. If you cancel it
        while it's pending or we reject it, it returns in full to your wallet automatically.</li>
    <li>A withdrawal that has been paid can't be reversed. Double-check the account, email or key you enter: if the
        details were wrong because of your mistake, we can't recover the payment.</li>
</ul>

<h2>5. How to request a refund</h2>
<p>Message <?= $support ?> from TREVIX messages or email <?= $mail ?> with your username, the date, the amount and the
    payment reference or receipt. We reply within 10 business days. When we approve a refund or an adjustment, you'll
    see it in your transactions as "TREVIX adjustment" with the reason, and you'll get a notification.</p>

<h2>6. Other cases</h2>
<ul>
    <li>We may deny a refund if we detect fraud or abuse, such as fake receipts or payments reversed after being
        credited.</li>
    <li>If you delete your account, any remaining balance can't be used or refunded afterwards: request a refund of
        eligible balance or withdraw your earnings first.</li>
    <li>Purchases are made with the TREVIX wallet, including in the iPhone and Android apps. The App Store and Google
        Play are not involved in these payments and don't handle their refunds.</li>
    <li>This policy doesn't limit any rights you have under applicable consumer protection law.</li>
</ul>
