-- Neurons -- les deux comptes Vertica de l'application et leurs droits.
-- Neurons lit avec neurones_reader et ecrit avec neurones_writer, jamais avec dbadmin.
-- Usage :
--   vsql -h <serveur> -d <base> -U dbadmin --     -v lecteur_mdp="'<mot de passe>'" -v ecrivain_mdp="'<mot de passe>'" -f vertica-comptes.sql

CREATE USER neurones_reader IDENTIFIED BY :lecteur_mdp;
CREATE USER neurones_writer IDENTIFIED BY :ecrivain_mdp;

GRANT USAGE ON SCHEMA apm TO neurones_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA apm TO neurones_reader;

GRANT USAGE, CREATE ON SCHEMA apm TO neurones_writer;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, ALTER ON ALL TABLES IN SCHEMA apm TO neurones_writer;

-- Les memes droits sur les tables que Neurons creera plus tard.
ALTER SCHEMA apm DEFAULT INCLUDE SCHEMA PRIVILEGES;
GRANT SELECT ON SCHEMA apm TO neurones_reader;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, ALTER ON SCHEMA apm TO neurones_writer;
