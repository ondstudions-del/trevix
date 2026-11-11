<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
$privacy = '<a href="' . e(url('legal.php', ['doc' => 'privacidad'])) . '">Privacy Policy</a>';
?>
<p>Welcome to TREVIX. These Terms and Conditions govern the use of the TREVIX social network, available on the web and
    in the iPhone and Android apps, operated by <?= e($legal['owner']) ?>, a company based in <?= e($legal['country']) ?>
    whose founder and owner is <?= e($legal['founder']) ?>. By creating an account or using TREVIX you accept these terms
    and the <?= $privacy ?>. If you do not agree, do not use the service.</p>

<nav class="legal__toc" aria-label="Contents of the terms">
    <ol>
        <li><a href="#requisitos">Who can use TREVIX</a></li>
        <li><a href="#cuenta">Your account</a></li>
        <li><a href="#servicio">The service</a></li>
        <li><a href="#contenido">Your content</a></li>
        <li><a href="#normas">Community guidelines</a></li>
        <li><a href="#mensajes">Messages and view once</a></li>
        <li><a href="#musica">Music and intellectual property</a></li>
        <li><a href="#verificado">Verified accounts</a></li>
        <li><a href="#comunidades">Communities, groups and events</a></li>
        <li><a href="#moderacion">Reports, moderation and penalties</a></li>
        <li><a href="#terminacion">Deactivating or deleting your account</a></li>
        <li><a href="#propiedad">TREVIX ownership</a></li>
        <li><a href="#terceros">Third-party services</a></li>
        <li><a href="#responsabilidad">Warranties and liability</a></li>
        <li><a href="#cambios">Changes to the terms</a></li>
        <li><a href="#ley">Governing law</a></li>
        <li><a href="#contacto">Contact</a></li>
    </ol>
</nav>

<h2 id="requisitos">1. Who can use TREVIX</h2>
<ul>
    <li>You must be at least 13 years old. If you are between 13 and 17, you need the authorization of your father,
        mother or legal guardian, who accepts these terms on your behalf.</li>
    <li>You must provide truthful information when you sign up, especially your date of birth and your email.</li>
    <li>You may not use TREVIX if the law prohibits you from doing so or if we have permanently suspended your account,
        unless we expressly authorize you.</li>
</ul>

<h2 id="cuenta">2. Your account</h2>
<ul>
    <li>You are responsible for the activity carried out from your account and for keeping your password secret. If you
        think someone accessed it without permission, change your password, log out of your other sessions from Settings
        and write to us.</li>
    <li>Your username may not impersonate another person, brand or organization, or be misleading. Some usernames are
        reserved.</li>
    <li>In the app you can keep up to 5 accounts signed in and switch between them. Each account must comply with these
        terms separately.</li>
    <li>If you turn on message encryption, keep your PIN safe: we do not know it and, if you forget it, previous
        encrypted messages cannot be recovered.</li>
    <li>You may not sell, rent or transfer your account.</li>
</ul>

<h2 id="servicio">3. The service</h2>
<p>TREVIX lets you post photos, videos, Reels and threads; share stories that last 24 hours and notes that last 6
    hours; follow other people; send messages and create groups; join communities; create events; listen to and
    upload music; and request verification. Using TREVIX is free.</p>
<p>We work to keep the service available and running well, but we may change, add or remove features, and suspend it
    temporarily for maintenance, security or reasons beyond our control. When a change significantly affects you, we
    will let you know.</p>

<h2 id="contenido">4. Your content</h2>
<ul>
    <li>What you post remains yours. So that we can display it, you grant us a non-exclusive, royalty-free, worldwide
        and limited license to host, reproduce, adapt (for example, resize a photo or create a video thumbnail) and
        display it within TREVIX according to the privacy settings you choose.</li>
    <li>The license ends when you delete the content or your account, except for what other people have already shared
        in a permitted way and for backups, which are overwritten over time.</li>
    <li>Only post content for which you hold the necessary rights. If other people appear with you, respect their image
        and their privacy.</li>
    <li>We do not use your content for advertising.</li>
</ul>

<h2 id="normas">5. Community guidelines</h2>
<p>To keep TREVIX a safe place, the following is not allowed:</p>
<ul>
    <li>Posting or sending illegal content, or promoting illegal activities.</li>
    <li>Any content that sexualizes or exploits minors. We have zero tolerance: we delete the account and report it to
        the competent authorities.</li>
    <li>Sexually explicit content or nudity, and sharing intimate images of another person without their consent.</li>
    <li>Harassing, threatening, intimidating or extorting other people, or inciting others to do so.</li>
    <li>Hate speech or discrimination based on race, ethnicity, nationality, religion, gender, sexual orientation,
        disability or any other condition.</li>
    <li>Gratuitously violent or graphic content, or the promotion of terrorism, self-harm or eating disorders.</li>
    <li>Impersonating another person, creating fake accounts or misrepresenting your identity.</li>
    <li>Spam, scams, chain messages, selling followers or likes, and manipulating the platform.</li>
    <li>Posting other people's personal data (phone number, address, documents) without their authorization.</li>
    <li>Infringing copyrights, trademarks or other intellectual property rights.</li>
    <li>Using bots, scripts or automated tools to create accounts, post, follow or extract data from TREVIX.</li>
    <li>Attempting to breach security, circumvent the limits of the service, access other people's accounts, distribute
        malicious software or interfere with the operation of TREVIX.</li>
    <li>Evading a penalty by creating another account.</li>
</ul>

<h2 id="mensajes">6. Messages and view once</h2>
<ul>
    <li>Your messages are private among the people in the chat or group. Any participant can report a message that
        violates these terms.</li>
    <li>View-once photos and videos can be opened only once per person. The app blocks screenshots and screen recording
        while they are being viewed, but it cannot prevent someone from photographing them with another device. Saving
        or spreading that content without the sender's consent is a serious violation.</li>
    <li>“Read receipts” are reciprocal: if you turn them off, you will not see who read your messages either.</li>
    <li>Respect the decision of anyone who does not want to receive your messages or who blocks you.</li>
    <li>The official @soport account replies with IX, an artificial intelligence assistant that provides guidance about
        TREVIX and logs your inquiries for the team. IX can make mistakes, cannot take action on your account or make
        moderation decisions, and its answers do not replace formal complaints, which you can send to <?= $mail ?>. We
        will never ask for your password or your PIN via chat.</li>
</ul>

<h2 id="musica">7. Music and intellectual property</h2>
<ul>
    <li>If you upload songs as an artist, you declare that you hold the rights or are authorized to publish them, and
        you grant us the license in section 4 to play them and to allow other people to use excerpts in their posts,
        stories, notes and profiles. Songs go through a review by the team before they appear in the library.</li>
    <li>Songs from the built-in free catalogs (Audius and Free To Use) are governed by the licenses of those
        catalogs.</li>
    <li>If you believe that some content infringes your copyright or trademark, write to us at <?= $mail ?> with your
        details, the link to the content and proof of your rights. We will review it and, if appropriate, remove it.
        Accounts that repeatedly infringe rights may be suspended.</li>
</ul>

<h2 id="verificado">8. Verified accounts</h2>
<p>The verified badge identifies creators, artists, public figures, brands and other accounts that requested it, meet
    the requirements published in the application (followers, activity and no recent warnings) and were approved by
    the team. By requesting it, you declare that the information you submit is true. Verification does not imply that
    we endorse the account's opinions.
    We may reject a request or remove the verified badge if the account no longer meets the requirements or violates
    these terms.</p>

<h2 id="comunidades">9. Communities, groups and events</h2>
<p>Whoever creates or manages a community or a group may set additional rules, accept or remove members and moderate
    its content, always within these terms. Whoever organizes an event is solely responsible for holding it, for the
    information they publish and for whatever happens at it; TREVIX only helps spread the word.</p>

<h2 id="moderacion">10. Reports, moderation and penalties</h2>
<ul>
    <li>You can report posts, comments, stories, messages, profiles and communities. The moderation team reviews the
        reports.</li>
    <li>Depending on the severity, we may remove the content, give you a warning, suspend your account temporarily or
        indefinitely, or delete it. In the most serious cases we may act without prior notice.</li>
    <li>When we suspend an account, we show you the reason and the end date, if any, when you log in.</li>
    <li>If you think we made a mistake, write to us at <?= $mail ?> from your account's email address and we will review
        the decision.</li>
</ul>

<h2 id="terminacion">11. Deactivating or deleting your account</h2>
<p>You can deactivate your account from Settings: your profile and your content are hidden until you log in again.
    You can also delete it: your account, your content and your messages are permanently erased, and this cannot be
    undone. The sections of these terms that by their nature must remain in effect (for example, those on liability
    and governing law) continue to apply.</p>

<h2 id="propiedad">12. TREVIX ownership</h2>
<p>The TREVIX name and logo, the design, the software and the other elements of the service belong to
    <?= e($legal['owner']) ?> and are protected by intellectual property laws. You may not copy, modify or use them
    without our written authorization, except as permitted by law.</p>

<h2 id="terceros">13. Third-party services</h2>
<p>TREVIX integrates third-party services, such as GIPHY GIFs and stickers, free music catalogs, OpenStreetMap maps
    and Google's Gemini API (for IX), and may display links to other sites. Those services have their own terms and we
    are not responsible for their content or their availability.</p>

<h2 id="responsabilidad">14. Warranties and liability</h2>
<ul>
    <li>Each person is responsible for the content they post and send. We do not review all content before it is
        published and we are not liable for the opinions or actions of users.</li>
    <li>We provide the service with due diligence, but we do not guarantee that it will work without interruptions or
        errors. To the extent permitted by law, we are not liable for indirect damages, lost profits or loss of data
        arising from the use of, or inability to use, TREVIX.</li>
    <li>Nothing in the foregoing limits the rights granted to you by Ley 1480 de 2011 (Estatuto del Consumidor —
        Colombian Consumer Protection Statute) and other mandatory regulations of <?= e($legal['country']) ?>.</li>
    <li>If you breach these terms and this gives rise to third-party claims against <?= e($legal['owner']) ?>, you will
        be liable for the resulting damages, in accordance with the law.</li>
</ul>

<h2 id="cambios">15. Changes to the terms</h2>
<p>We may update these terms to reflect changes in the service or in the law. If the change is significant, we will
    notify you on the web or in the app before it takes effect. If you continue to use TREVIX after that date, we will
    consider that you accept the new version; if you do not agree, you can delete your account.</p>

<h2 id="ley">16. Governing law</h2>
<p>These terms are governed by the laws of the Republic of <?= e($legal['country']) ?>. Any dispute will first be
    addressed directly by writing to us; if that is not possible, it will be heard by the competent courts of
    <?= e($legal['country']) ?>, without prejudice to your right to go to the Superintendencia de Industria y Comercio
    (Superintendence of Industry and Commerce). If any clause is found to be invalid, the remaining clauses remain in
    effect.</p>

<h2 id="contacto">17. Contact</h2>
<p>For questions about these terms, to report a problem or to request a review of a decision, write to us at
    <?= $mail ?>. Version in effect since <?= e(t($legal['updated'])) ?>.</p>
