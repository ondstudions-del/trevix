<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$support = '<a href="' . e(url('profile.php', ['u' => (string) \Trevix\Core\Config::get('app.ix.username', 'soport')])) . '">@' . e((string) \Trevix\Core\Config::get('app.ix.username', 'soport')) . '</a>';
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
?>
<p>Esta política explica cuándo y cómo devolvemos dinero del monedero de TREVIX: las recargas, las suscripciones a
    colaboradores, los regalos y los retiros de ganancias. Complementa los
    <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>">Términos y condiciones</a>. Todos los importes están
    en dólares estadounidenses (USD).</p>

<h2>1. Recargas del monedero</h2>
<ul>
    <li><strong>Recargas en revisión.</strong> Mientras el equipo no haya revisado una recarga puedes cancelarla desde
        Monedero. Si la cancelas o la rechazamos (por ejemplo, porque el comprobante no coincide con un pago recibido)
        y el dinero sí llegó a nuestra cuenta, te lo devolvemos por el mismo medio de pago cuando nos escribas con la
        referencia.</li>
    <li><strong>Saldo no usado: 30 días.</strong> Puedes pedir la devolución del saldo recargado que no hayas gastado
        si lo solicitas dentro de los 30 días siguientes a la recarga. Se devuelve por el mismo medio de pago con el que
        recargaste y por el importe que se acreditó. Si ya usaste una parte, se devuelve el resto de esa recarga.</li>
    <li>Pasados los 30 días, el saldo sigue disponible para usarlo dentro de TREVIX, pero ya no se devuelve.</li>
    <li>Lo que recargas no se puede retirar como ganancia: solo se retira lo ganado como colaborador y con regalos.</li>
</ul>

<h2>2. Suscripciones a colaboradores</h2>
<p>Al suscribirte obtienes acceso inmediato al contenido exclusivo del colaborador. Por eso las suscripciones
    <strong>no son reembolsables</strong>: tampoco por días sin usar, si dejas de seguir al colaborador o si este pausa
    su plan (conservas el acceso hasta la fecha de vencimiento). Solo hay reembolso en estos casos:</p>
<ul>
    <li><strong>Cobro duplicado:</strong> se descontó dos veces la misma compra por un error.</li>
    <li><strong>Error técnico de TREVIX:</strong> se cobró un importe distinto al que se mostraba o un fallo de la
        plataforma te impidió ver el contenido por el que pagaste.</li>
    <li><strong>Cuenta del colaborador retirada:</strong> si el equipo elimina o suspende la cuenta del colaborador por
        incumplir las normas, devolvemos la parte proporcional a los días de acceso que te quedaban.</li>
</ul>
<p>Estos reembolsos se hacen siempre <strong>a tu monedero de TREVIX</strong>, no a un medio de pago externo. Debes
    reportar el cobro duplicado o el error dentro de los 30 días siguientes al cobro. Cuando reembolsamos una compra,
    podemos descontar del monedero del colaborador lo que recibió por ella.</p>

<h2>3. Regalos</h2>
<ul>
    <li>Los regalos se pagan con el saldo del monedero. Puedes enviarlos al comprarlos o guardarlos en «Mis regalos»
        para enviarlos después; cada regalo guardado conserva el precio que pagaste.</li>
    <li>Los regalos <strong>no son reembolsables</strong> una vez enviados, porque el importe se acredita de inmediato a
        quien lo recibe. Los regalos guardados que aún no envías tampoco se convierten de nuevo en saldo.</li>
    <li>Quien recibe un regalo obtiene su precio menos la comisión de TREVIX que se indica en la tienda de regalos. Ese
        importe se puede retirar como ganancia.</li>
    <li>Solo hay reembolso, a tu monedero, por un cobro duplicado o un error técnico de TREVIX reportado dentro de los
        30 días. En ese caso podemos descontar del monedero de quien lo recibió lo que se le acreditó.</li>
</ul>

<h2>4. Retiros de ganancias</h2>
<ul>
    <li>Al pedir un retiro, el monto se descuenta de tu saldo y queda en revisión. Si lo cancelas mientras está
        pendiente o lo rechazamos, vuelve completo a tu monedero de forma automática.</li>
    <li>Un retiro ya pagado no se puede revertir. Revisa bien la cuenta, el correo o la llave que escribes: si los datos
        eran incorrectos por un error tuyo, no podemos recuperar el pago.</li>
</ul>

<h2>5. Cómo pedir un reembolso</h2>
<p>Escríbele a <?= $support ?> desde los mensajes de TREVIX o al correo <?= $mail ?> con tu usuario, la fecha, el importe
    y la referencia o el comprobante del pago. Respondemos en un máximo de 10 días hábiles. Cuando aprobamos un
    reembolso o un ajuste, lo verás en tus movimientos como «Ajuste de TREVIX» con el motivo y te llegará un aviso.</p>

<h2>6. Otros casos</h2>
<ul>
    <li>Podemos negar un reembolso si detectamos fraude o abuso, por ejemplo comprobantes falsos o pagos revertidos
        después de acreditados.</li>
    <li>Si eliminas tu cuenta, el saldo que quede no se podrá usar ni devolver después: pide antes la devolución del
        saldo que esté dentro del plazo o retira tus ganancias.</li>
    <li>Las compras se hacen con el monedero de TREVIX, también en las apps de iPhone y Android. App Store y Google Play
        no intervienen en estos pagos ni gestionan sus reembolsos.</li>
    <li>Esta política no limita los derechos que te reconozca la ley de protección al consumidor aplicable.</li>
</ul>
