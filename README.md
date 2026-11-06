# sysinfo

Un résumé de la machine Linux en un seul script bash : un tableau de bord
coloré qui rassemble l'essentiel de l'état du système.

## Utilisation

```bash
./sysinfo.sh        # mode résumé
./sysinfo.sh -v     # mode verbeux, plus de détails
sudo ./sysinfo.sh   # recommandé : certaines sections demandent les droits root
```

Sans les droits root, le script fonctionne quand même : les sections qui en
ont besoin sont simplement ignorées ou signalées.

## Sections

| Section | Contenu |
|---|---|
| Système | nom d'hôte, distribution, noyau, architecture, virtualisation, uptime, charge |
| Matériel | modèle de CPU et nombre de cœurs, RAM, swap |
| Disques | occupation des partitions (orange ≥ 75 %, rouge ≥ 90 %) |
| Mises à jour | paquets à mettre à jour (apt, dnf ou pacman), nombre de paquets installés |
| Services | services systemd en cours, activés au démarrage, en échec |
| Réseau | interfaces et adresses, passerelle, DNS, ports en écoute, pare-feu |
| Utilisateurs | sessions ouvertes, comptes UID 0, membres sudo/wheel, comptes avec shell |
| Tâches planifiées | entrées crontab des utilisateurs, fichiers de `/etc/cron.d` |
| Sécurité | dernières connexions, connexions échouées (root), binaires setuid, erreurs du journal du jour |

En mode verbeux, le script ajoute la date du dernier boot, la liste des services
en cours, le détail des ports en écoute et des comptes, ainsi que les
5 processus qui consomment le plus de mémoire.

## Dépendances

Seulement des outils standards : `bash`, `coreutils`, `procps` (`free`, `ps`,
`uptime`), `iproute2` (`ip`, `ss`). `systemctl`, `journalctl`, `ufw`,
`firewall-cmd` et `iptables` sont utilisés s'ils sont présents.

Les couleurs sont désactivées automatiquement quand la sortie n'est pas un
terminal (redirection vers un fichier, par exemple).
