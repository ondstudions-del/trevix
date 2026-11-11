<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
?>
<p>At TREVIX we respect your privacy. This policy explains what personal data we process when you use the website
    <a href="<?= e(url()) ?>"><?= e(parse_url(url(), PHP_URL_HOST) ?: 'trevix.ond-s.com') ?></a> and the TREVIX apps for
    iPhone and Android, what we use it for, whom we share it with and how you can exercise your rights. It is governed
    by Ley Estatutaria 1581 de 2012 (Statutory Law 1581 of 2012), Decreto 1377 de 2013 (Decree 1377 of 2013, compiled
    in Decreto 1074 de 2015) and other personal data protection regulations of the Republic of
    <?= e($legal['country']) ?>.</p>

<nav class="legal__toc" aria-label="Contents of the policy">
    <ol>
        <li><a href="#responsable">Data controller</a></li>
        <li><a href="#datos">Data we process</a></li>
        <li><a href="#finalidades">What we use it for</a></li>
        <li><a href="#autorizacion">Authorization</a></li>
        <li><a href="#mensajes">Messages, encryption and view once</a></li>
        <li><a href="#visibilidad">What other people see</a></li>
        <li><a href="#terceros">Whom we share data with</a></li>
        <li><a href="#transferencias">International transfers</a></li>
        <li><a href="#conservacion">How long we keep it</a></li>
        <li><a href="#derechos">Your rights</a></li>
        <li><a href="#procedimiento">How to exercise them</a></li>
        <li><a href="#menores">Minors</a></li>
        <li><a href="#seguridad">Security</a></li>
        <li><a href="#permisos">App permissions</a></li>
        <li><a href="#cambios">Changes and effective date</a></li>
    </ol>
</nav>

<h2 id="responsable">1. Data controller</h2>
<ul class="legal__facts">
    <li><strong>Controller:</strong> <?= e($legal['owner']) ?>, owner and operator of TREVIX.</li>
    <li><strong>Founder and owner of <?= e($legal['owner']) ?>:</strong> <?= e($legal['founder']) ?>.</li>
    <li><strong>Country:</strong> <?= e($legal['country']) ?>.</li>
    <li><strong>Privacy and support email:</strong> <?= $mail ?>.</li>
</ul>

<h2 id="datos">2. Data we process</h2>
<p><strong>What you give us when you sign up:</strong> display name, username, email address, date of birth and
    password. Your password is never stored as is: we only store an encrypted fingerprint (hash) that cannot be used to
    recover it.</p>
<p><strong>Your profile details, if you choose to add them:</strong> profile and cover photo, bio, current city and
    hometown, relationship status, gender, links to other social networks, contact details and your profile song. You
    choose who sees these details (everyone, followers, friends or no one) and whether your birth year is shown.</p>
<p><strong>What you post and share:</strong> posts, photos, videos, Reels, threads, comments, stories, notes, polls,
    mentions, events, communities, songs you upload as an artist and the locations you choose to add.</p>
<p><strong>Your activity on TREVIX:</strong> whom you follow and who follows you, likes, reactions, saves, reports,
    blocks, story and note views, your close friends list and your privacy settings.</p>
<p><strong>Your messages:</strong> texts, photos, videos, voice notes, GIFs, stickers, locations and reactions that you
    send in chats and groups, along with delivery and read records (see section 5).</p>
<p><strong>Minimal technical data:</strong> the IP address you connect from and the device name of each app session,
    which we use for security (limiting login attempts, detecting abuse and showing you your active sessions).</p>
<p><strong>If you request verification:</strong> the full name, category and note you submit, and the figures from
    your account that we use to assess the request (followers and average likes).</p>
<p><strong>Sensitive data:</strong> we do not ask you for sensitive data (racial or ethnic origin, political
    orientation, religious beliefs, health, sex life or biometric data). If you choose to include it in your content,
    you do so voluntarily and you are not required to do so.</p>
<p>We do not upload your contact list to our servers, we do not use facial recognition and we do not track your
    location: we only store a location when you add it to a post, a story or a message.</p>

<h2 id="finalidades">3. What we use it for</h2>
<ul>
    <li>Creating and managing your account, logging you in and keeping your sessions open.</li>
    <li>Showing your profile and your content to the people you choose, building your home feed, Explore and people
        suggestions, and delivering your messages.</li>
    <li>Sending you notifications about your activity (followers, likes, comments, messages) and emails about your
        account: email verification, password recovery and security changes. We do not send advertising.</li>
    <li>Maintaining security: limiting login attempts, preventing spam and fake accounts, and reviewing reports of
        content that violates the <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>">Terms and
        Conditions</a>.</li>
    <li>Handling your requests, inquiries and complaints, including through IX, our artificial intelligence support
        assistant, and welcoming you when you create your account.</li>
    <li>Complying with legal obligations and responding to requests from competent authorities.</li>
</ul>
<p><strong>We do not sell or rent your personal data, we do not show advertising and we do not use third-party
    tracking or analytics tools.</strong></p>

<h2 id="autorizacion">4. Authorization</h2>
<p>By creating your account and checking the acceptance box, you give us your prior, express and informed
    authorization to process your data in accordance with this policy. You can revoke it at any time by deleting your
    account from Settings or by writing to us at <?= $mail ?>, unless there is a legal or contractual duty to retain
    it.</p>

<h2 id="mensajes">5. Messages, encryption and view once</h2>
<ul>
    <li><strong>End-to-end encryption:</strong> in the app, chats and groups are encrypted when everyone has the app set
        up. Content is encrypted on your phone and our servers only store the encrypted message and your key protected
        with the 6-digit PIN you choose: we cannot read those messages or recover your PIN. If someone in the chat only
        uses the web, that chat is not encrypted.</li>
    <li><strong>Unencrypted messages:</strong> they are stored on our servers so they can be delivered. Only the
        moderation team can review a message, and only when someone reports it.</li>
    <li><strong>View once:</strong> view-once photos and videos are deleted from the server when everyone in the chat
        has opened them, or after 14 days if they are not opened. While they are being viewed, the app blocks
        screenshots and screen recording, but it cannot prevent someone from photographing them with another
        device.</li>
    <li><strong>Disappearing messages:</strong> if you turn them on, they are deleted after the time you choose (24
        hours, 7 or 90 days).</li>
    <li><strong>Delivery and read status:</strong> we record up to which message each person in the chat has received
        and read, in order to show it in “Info”. “Read receipts” are reciprocal: if you turn them off, no one sees when
        you read their messages and you do not see who read yours either.</li>
    <li><strong>Support chat (IX):</strong> the official @soport account replies with IX, an artificial intelligence.
        That chat is not end-to-end encrypted. To reply to you, we send Google (Gemini) the latest messages in that
        chat, the last regular photo you send in it and basic details of your account (display name, username, sign-up
        date, whether you verified your email, whether you have the verified badge, whether your account is private,
        and how many followers, posts and warnings you have). We never send your email, your password or your other
        chats. IX classifies your inquiry (question, bug, suggestion, report, grievance, complaint or request) and, when
        needed, logs a summary for the team to review. Members of the support team can read that chat and reply to you
        in it.</li>
</ul>

<h2 id="visibilidad">6. What other people see</h2>
<p>Your display name, username and profile photo are always visible so that people can find you. If your account is
    private, only your approved followers see your posts and stories. You can limit who sends you messages, who sees
    your activity and who sees your profile details, share stories and notes only with your close friends, and block
    anyone. Keep in mind that whatever you post with a public account can be seen by anyone who uses TREVIX, and that
    whoever sees it could share it outside the platform.</p>

<h2 id="terceros">7. Whom we share data with</h2>
<p>We only share what is necessary with these providers, which act as processors or provide a technical service:</p>
<ul>
    <li><strong>Hostinger:</strong> hosts TREVIX's servers, database, files and email.</li>
    <li><strong>GIPHY:</strong> we search for GIFs and stickers from our server, but the images are loaded from GIPHY's
        servers, which receive your IP address and technical data about your device.</li>
    <li><strong>Audius and Free To Use:</strong> free music catalogs. Searches are made from our server, without sending
        your identity; some songs may be loaded from their servers.</li>
    <li><strong>OpenStreetMap (Nominatim):</strong> when you add a location, we send only the coordinates from our
        server to get the name of the place. Map links open OpenStreetMap or Google Maps, which have their own
        policies.</li>
    <li><strong>Google (Gemini API):</strong> generates IX's replies in the chat with @soport and the welcome messages,
        using the data described in section 5. For the welcome message we do not send your name or any other data that
        identifies you. Google processes that information under its terms for the Gemini API.</li>
    <li><strong>Google Fonts:</strong> the app may download fonts from Google's servers, which receive your IP
        address.</li>
    <li><strong>Apple App Store and Google Play:</strong> they distribute the apps; whatever they process when you
        download them is governed by their policies.</li>
    <li><strong>Authorities:</strong> only when a court order or a competent authority requires it in accordance with
        the law, or to protect a person's life or safety.</li>
</ul>
<p>App notifications work by checking our own servers: we do not use Firebase or third-party notification services for
    advertising purposes.</p>

<h2 id="transferencias">8. International transfers</h2>
<p>Our providers' servers may be located outside <?= e($legal['country']) ?>. By accepting this policy you authorize
    the transmission of your data to those servers, which is done solely to provide the service and with providers that
    apply adequate security measures.</p>

<h2 id="conservacion">9. How long we keep it</h2>
<ul>
    <li><strong>Your account and your content:</strong> for as long as you have the account. If you deactivate it, it is
        hidden until you log in again.</li>
    <li><strong>When you delete your account:</strong> we immediately and permanently erase your profile, posts,
        stories, comments, messages, files and songs. Hosting backups may retain data for a limited time until they are
        overwritten.</li>
    <li><strong>Stories:</strong> they are deleted along with their files after 24 hours, except those you save to your
        highlights.
        <strong>Notes:</strong> after 6 hours.</li>
    <li><strong>App sessions:</strong> they expire after 90 days of inactivity or when you log out.</li>
    <li><strong>Links sent by email:</strong> verification links expire after 48 hours, password recovery links after
        one hour and email change links after 24 hours.</li>
    <li><strong>Support requests:</strong> the summaries logged by IX are kept for as long as you have the account and
        are deleted when you delete it.</li>
    <li><strong>Moderation records:</strong> the team's decisions are kept for the security of the platform and to
        handle complaints.</li>
</ul>

<h2 id="derechos">10. Your rights</h2>
<p>As the owner of your data, you have the right to:</p>
<ul>
    <li>Know, update and correct your data. You can do this directly from Settings and Edit profile.</li>
    <li>Request proof of the authorization you gave us.</li>
    <li>Be informed about how we use your data.</li>
    <li>Revoke your authorization and request the deletion of your data when legal principles and guarantees are not
        respected. You can delete your account at any time from Settings.</li>
    <li>Access your personal data free of charge.</li>
    <li>File complaints with the Superintendencia de Industria y Comercio (SIC — Superintendence of Industry and
        Commerce), after having completed the inquiry or complaint process with us.</li>
</ul>

<h2 id="procedimiento">11. How to exercise them</h2>
<p>Write to us at <?= $mail ?> from your account's email address, stating your username and what you are requesting.</p>
<ul>
    <li><strong>Inquiries:</strong> we answer them within a maximum of 10 business days. If that is not possible, we will
        let you know the reason and the new date, which will not exceed 5 additional business days.</li>
    <li><strong>Complaints</strong> (correction, update, deletion or non-compliance): they must include your
        identification, a description of the facts and any documents you wish to rely on. We handle them within a
        maximum of 15 business days, extendable by up to 8 additional business days with prior notice. If the complaint
        is incomplete, we will ask you to complete it within 5 days; if 2 months pass without a response, it will be
        deemed withdrawn.</li>
</ul>

<h2 id="menores">12. Minors</h2>
<p>TREVIX is not directed at children under 13 and does not allow anyone who states a younger age to create an
    account. People between 13 and 17 must have the authorization of their father, mother or legal guardian. We process
    the data of children and adolescents respecting their best interests and their fundamental rights. If you are a
    legal guardian and believe that a minor gave us their data without your authorization, write to us at <?= $mail ?>
    and we will delete the account.</p>

<h2 id="seguridad">13. Security</h2>
<p>We use encrypted connections (HTTPS), passwords stored with secure hash functions, protection against cross-site
    request forgery (CSRF) and other common attacks, login attempt limits, sessions that expire and secure device
    storage (keychain) for the app's sessions and keys. No system is infallible: if we detect an incident that affects
    your data, we will inform you and report it to the authorities when required by law.</p>

<h2 id="permisos">14. App permissions</h2>
<p>The app only asks for permissions when you use the feature that needs them, and you can revoke them from your
    phone's settings:</p>
<ul>
    <li><strong>Camera and microphone:</strong> to take photos and record videos, stories and voice notes.</li>
    <li><strong>Photos and files:</strong> to choose what you want to post or send.</li>
    <li><strong>Location:</strong> only when you choose to share where you are in a message or add it to a
        post.</li>
    <li><strong>Contacts:</strong> only if you use “Invite contacts” in Settings, to choose whom to send an SMS
        invitation to. The list is read on your phone and is never sent to our servers.</li>
    <li><strong>Notifications:</strong> to alert you about messages and activity. On Android, if you turn on “Instant
        alerts”, the app keeps a foreground service running with a fixed, silent notification that checks our servers
        to deliver your messages even when the app is closed. You can turn it off in Settings.</li>
</ul>

<h2 id="cambios">15. Changes and effective date</h2>
<p>This policy is effective as of <?= e(t($legal['updated'])) ?>. If we make significant changes, we will notify you on
    the web or in the app before they take effect. Your data will be processed for as long as you keep your account and
    for the time necessary to fulfill the purposes described and our legal obligations.</p>
