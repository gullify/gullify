<?php
/**
 * Envoie un vrai courriel, avec les réglages du .env.
 *
 * À passer dès que MAIL_SMTP_PASSWORD est renseigné : c'est la seule façon de
 * savoir si les confirmations d'inscription arriveront vraiment.
 *
 *   docker exec gullify php /app/scripts/test-mail.php moi@exemple.ca
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/AppConfig.php';
require_once __DIR__ . '/../src/Mailer.php';

$destinataire = $argv[1] ?? '';
if (!filter_var($destinataire, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage : test-mail.php adresse@exemple.ca\n");
    exit(2);
}

$poste = Mailer::fromConfig();
printf(
    "Pilote : %s | expéditeur : %s | envoi réel : %s\n",
    (string)AppConfig::get('mail.driver'),
    (string)AppConfig::get('mail.from'),
    $poste->envoiReel() ? 'oui' : 'NON (rien ne partira)'
);

try {
    $poste->envoyer(
        $destinataire,
        'Essai d\'envoi — GulliFY',
        "Si tu lis ceci, les courriels de GulliFY partent correctement.\n\n— GulliFY",
        '<p>Si tu lis ceci, les courriels de GulliFY partent correctement.</p><p>— GulliFY</p>'
    );
    echo "✓ accepté par le serveur d'envoi\n";
    if (!$poste->envoiReel()) {
        echo "  (écrit dans " . (AppConfig::get('mail.log') ?: sys_get_temp_dir() . '/gullify-courriels.log') . ")\n";
    }
} catch (Throwable $e) {
    echo "✗ " . $e->getMessage() . "\n";
    exit(1);
}
