<?php
/**
 * La page qu'on atteint en cliquant dans le courriel de confirmation.
 *
 * Elle est lue par quelqu'un qui a laissé un installateur ouvert sur une autre
 * fenêtre : elle doit dire en une phrase que c'est fait, et où retourner. Même
 * habillage que l'accueil — c'est la même maison.
 */
declare(strict_types=1);

require_once __DIR__ . '/../src/Registry.php';

$fqdn = null;
$probleme = null;

if (!Registry::actif()) {
    http_response_code(404);
    $probleme = 'Ce serveur ne distribue pas de sous-domaines.';
} else {
    try {
        $fqdn = (new Registry())->confirmer((string)($_GET['code'] ?? ''));
    } catch (RuntimeException $e) {
        http_response_code(410);
        $probleme = $e->getMessage();
    } catch (Throwable $e) {
        error_log('confirmer-serveur.php : ' . $e->getMessage());
        http_response_code(500);
        $probleme = 'Quelque chose a lâché de notre côté. Réessaie dans un moment.';
    }
}

function e(?string $s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title><?= $fqdn ? 'Serveur confirmé' : 'Lien expiré' ?> — GulliFY</title>
<link rel="icon" href="/favicon.ico">
<link rel="stylesheet" href="/assets/base.css">
<link rel="stylesheet" href="/assets/site.css">
<style>
  .confirmation { max-width: 620px; margin: 0 auto; padding: 5rem 1.25rem; text-align: center; }
  .pastille {
    width: 76px; height: 76px; margin: 0 auto 1.6rem;
    display: grid; place-items: center; border-radius: 50%;
    background: rgba(63, 169, 140, .14); border: 1px solid rgba(63, 169, 140, .35);
    color: #5ad79b;
  }
  .pastille.rate { background: rgba(255, 128, 128, .12); border-color: rgba(255, 128, 128, .35); color: #ff8080; }
  .confirmation h1 { font-size: clamp(1.6rem, 4vw, 2.2rem); font-weight: 700; letter-spacing: -.03em; }
  .confirmation p { color: var(--texte-attenue); line-height: 1.65; margin-top: .9rem; }
  .adresse {
    display: inline-block; margin-top: 1.5rem; padding: .7em 1.2em;
    border-radius: var(--rayon); background: var(--fond-champ);
    border: 1px solid var(--bordure); color: var(--texte-vif);
    font-weight: 700; font-size: 1.1rem; word-break: break-all;
  }
  .suite { margin-top: 2rem; font-size: .95rem; }
</style>
</head>
<body>
<main class="confirmation">
  <?php if ($fqdn): ?>
    <div class="pastille" aria-hidden="true">
      <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12.5 5.2 5.2L20 7"/></svg>
    </div>
    <h1>C'est confirmé</h1>
    <p>Ton adresse est réservée. Elle pointera vers ton serveur dès que
      l'installation sera terminée.</p>
    <span class="adresse"><?= e($fqdn) ?></span>
    <p class="suite"><strong>Retourne à la fenêtre d'installation</strong> —
      elle a déjà repris toute seule.</p>
  <?php else: ?>
    <div class="pastille rate" aria-hidden="true">
      <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 7v7M12 17.5v.01"/><circle cx="12" cy="12" r="9"/></svg>
    </div>
    <h1>Ce lien ne marche plus</h1>
    <p><?= e($probleme) ?></p>
    <p class="suite"><a href="/">Revenir à l'accueil</a></p>
  <?php endif; ?>
</main>
</body>
</html>
