<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
?>
<p>The TREVIX website uses only the cookies and browser storage that are strictly necessary for it to work. We do not
    use advertising, analytics or third-party tracking cookies, so you do not need to accept them to browse. More
    details about your data in the
    <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>">Privacy Policy</a>.</p>

<h2>1. Session cookie</h2>
<p><code>trevix_session</code> keeps you logged in and protects forms against forged requests (CSRF). It is a
    first-party cookie, <code>HttpOnly</code> (not accessible from JavaScript), secure over HTTPS connections and set
    with <code>SameSite=Lax</code>. It is deleted when you close the browser or log out, and the session expires after 2
    hours of inactivity.</p>

<h2>2. Local storage</h2>
<p>We store the following in your browser, without sending it to our servers:</p>
<ul>
    <li><code>trevix.prefs</code>: your display and accessibility preferences, such as reducing animations or the
        text size.</li>
    <li><code>trevix.appOpen</code>: remembers that you dismissed the prompt to open TREVIX in the app.</li>
    <li><code>trevix.previewBanner</code>: remembers that you dismissed the preview notice.</li>
</ul>

<h2>3. Third-party content</h2>
<p>GIFs and stickers are loaded from GIPHY's servers, which may receive your IP address and technical data about your
    browser in accordance with their own policy. TREVIX does not set third-party cookies.</p>

<h2>4. How to control them</h2>
<p>You can delete cookies and local storage from your browser settings. If you delete the session cookie, you will
    have to log in again. If you have any questions, write to us at
    <a href="mailto:<?= e($legal['email']) ?>"><?= e($legal['email']) ?></a>.</p>
