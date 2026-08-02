<?php
/**
 * Interprète réel d'une piste.
 *
 * Sur une compilation (album « Various Artists »), chaque piste a son propre
 * interprète : l'artiste lié (`songs.artist_id`, rempli par le scan) ou, à
 * défaut, le tag ID3 conservé dans `songs.track_artist`. Partout ailleurs la
 * piste n'a rien de plus précis que l'artiste de l'album, sur lequel on
 * retombe.
 *
 * Toute requête qui renvoie des titres doit utiliser ces fragments : le
 * lecteur (mobile ET Android Auto) affiche `artistName`, et doit y montrer
 * l'artiste de la chanson, pas « Various Artists ».
 *
 * Alias attendus : `s` = songs, `a` = l'artiste de l'album, `ta` = la
 * jointure ajoutée par TRACK_ARTIST_JOIN.
 */

/** À ajouter au FROM, à côté de la jointure sur `artists a`. */
const TRACK_ARTIST_JOIN = 'LEFT JOIN artists ta ON ta.id = s.artist_id';

/** Nom à afficher pour la piste. */
const TRACK_ARTIST_NAME =
    "COALESCE(NULLIF(ta.name, ''), NULLIF(s.track_artist, ''), a.name)";

/**
 * Identifiant navigable de l'interprète : celui de l'artiste lié, sinon celui
 * de l'album quand la piste n'a pas d'interprète distinct — mais NULL quand le
 * nom ne vient que d'un tag ID3 sans fiche artiste correspondante (ouvrir
 * celle de l'album serait trompeur).
 */
const TRACK_ARTIST_ID = "COALESCE(ta.id, CASE
        WHEN NULLIF(s.track_artist, '') IS NULL OR s.track_artist = a.name
        THEN a.id END)";
