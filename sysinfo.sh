#!/usr/bin/env bash
#
# sysinfo.sh - Tableau de bord récapitulatif d'un système Linux
# Usage: ./sysinfo.sh [-v]   (-v = mode verbeux, plus de détails)
# Fonctionne en root (recommandé) ou utilisateur normal : les sections
# nécessitant des privilèges sont simplement ignorées.
#
set -u

VERBOSE=0
[[ "${1:-}" == "-v" ]] && VERBOSE=1

# ---------- couleurs ----------
if [[ -t 1 ]]; then
  B="\033[1m"; R="\033[0m"
  C_title="\033[1;36m"; C_hdr="\033[1;37m"
  C_ok="\033[1;32m"; C_warn="\033[1;33m"; C_crit="\033[1;31m"
  C_dim="\033[2m"
else
  B=""; R=""; C_title=""; C_hdr=""; C_ok=""; C_warn=""; C_crit=""; C_dim=""
fi

LINE="────────────────────────────────────────────────────────────────────"

title() { printf "\n${C_title}${B}  %s${R}\n" "$1"; }
sep()   { printf "  ${C_dim}%s${R}\n" "$LINE"; }
row()   { printf "  ${C_hdr}%-18s${R} %s\n" "$1:" "$2"; }
warn()  { printf "  ${C_hdr}%-18s${R} ${C_warn}%s${R}\n" "$1:" "$2"; }
crit()  { printf "  ${C_hdr}%-18s${R} ${C_crit}%s${R}\n" "$1:" "$2"; }
ok()    { printf "  ${C_hdr}%-18s${R} ${C_ok}%s${R}\n" "$1:" "$2"; }
sect()  { title "$1"; sep; }

cmd_exists() { command -v "$1" &>/dev/null; }
is_root()    { [[ $EUID -eq 0 ]]; }

# =====================================================================
printf "${C_title}${B}"
cat <<'BANNER'
   _____         _
  / ____|_  ____ | |_ ___ _ ____      _____ _   _ _ __   ___
 | (___ (_)/ __|| __/ _ \ '__\ \ /\ / / _ \ | | | '_ \ / __|
  \___ \ | |__ | ||  __/ |   \ V  V /  __/ |_| | |_) | (__
  ____) / |  __| \__\___|_|    \_/\_/ \___|\__, | .__/ \___|
 |_____/  |_|                             |___/|_|
BANNER
printf "${R}\n"
printf "  Tableau de bord système - %s\n" "$(date '+%d/%m/%Y %H:%M:%S')"
sep

# ---------- OS et noyau ----------
sect "SYSTÈME"
row "Hostname" "$(hostname 2>/dev/null || cat /etc/hostname)"
[[ -r /etc/os-release ]] && . /etc/os-release && row "Distribution" "${PRETTY_NAME:-inconnue}"
row "Noyau" "$(uname -r)"
row "Architecture" "$(uname -m)"
row "Virtualisation" "$(systemd-detect-virt 2>/dev/null || echo 'inconnue')"
row "Uptime" "$(uptime -p 2>/dev/null || uptime | sed 's/.*up //;s/,.*load/ (load/')"
read -r l1 l5 l15 _ < /proc/loadavg
row "Charge (1/5/15m)" "$l1 / $l5 / $l15"
[[ ${VERBOSE} -eq 1 ]] && row "Dernier boot" "$(uptime -s 2>/dev/null)"

# ---------- CPU et mémoire ----------
sect "MATÉRIEL"
CPUMODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
[[ -z $CPUMODEL ]] && CPUMODEL=$(lscpu 2>/dev/null | awk -F: '/^Model name/{gsub(/^ */,"",$2);print $2;exit}')
row "CPU" "$CPUMODEL ($(nproc) cœurs)"
mem=$(free -h --si 2>/dev/null | awk '/Mem:/{print $2}'); memu=$(free -h --si | awk '/Mem:/{print $3}')
row "RAM" "$memu utilisés / $mem"
swap_total=$(free | awk '/Swap:/{print $2}')
if [[ $swap_total -gt 0 ]]; then
  sw=$(free -h --si | awk '/Swap:/{print $3}'); row "Swap" "$sw utilisés / $(free -h --si | awk '/Swap:/{print $2}')"
else
  warn "Swap" "aucun"
fi

# ---------- Disques ----------
sect "DISQUES"
df -h -x tmpfs -x devtmpfs -x squashfs --output=target,size,used,pcent 2>/dev/null | \
  tail -n +2 | while read -r mnt sz used pct; do
    p=${pct%\%}
    if [[ $p -ge 90 ]]; then printf "  ${C_crit}%-22s${R} %s / %s  %s\n" "$mnt" "$used" "$sz" "$pct"
    elif [[ $p -ge 75 ]]; then printf "  ${C_warn}%-22s${R} %s / %s  %s\n" "$mnt" "$used" "$sz" "$pct"
    else printf "  %-22s %s / %s  %s\n" "$mnt" "$used" "$sz" "$pct"; fi
  done

# ---------- Mises à jour ----------
sect "MISES À JOUR"
if cmd_exists apt; then
  n=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
  if [[ $n -eq 0 ]]; then ok "Debian/Ubuntu" "système à jour"
  else warn "Debian/Ubuntu" "$n paquet(s) à mettre à jour"; fi
elif cmd_exists dnf; then
  n=$(dnf -q check-update 2>/dev/null | grep -c '^[a-zA-Z0-9]')
  if [[ $n -eq 0 ]]; then ok "RHEL/Fedora" "système à jour"
  else warn "RHEL/Fedora" "$n paquet(s) à mettre à jour"; fi
elif cmd_exists pacman; then
  n=$(pacman -Qu 2>/dev/null | wc -l)
  if [[ $n -eq 0 ]]; then ok "Arch" "système à jour"
  else warn "Arch" "$n paquet(s) à mettre à jour"; fi
else
  row "Gestionnaire" "non détecté"
fi
row "Paquets installés" "$( { dpkg -l 2>/dev/null | grep -c '^ii'; rpm -qa 2>/dev/null | wc -l; pacman -Q 2>/dev/null | wc -l; } | grep -m1 -v '^0$')"

# ---------- Services ----------
sect "SERVICES"
if command -v systemctl &>/dev/null && systemctl list-units &>/dev/null 2>&1; then
  running=$(systemctl list-units --type=service --state=running --no-legend | wc -l)
  enabled=$(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l)
  failed=$(systemctl --failed --no-legend 2>/dev/null | grep -c '\.service')
  ok   "En cours"      "$running service(s)"
  row  "Au démarrage"  "$enabled activé(s)"
  if [[ $failed -gt 0 ]]; then
    crit "En échec" "$failed service(s)"
    systemctl --failed --no-legend | awk '{printf "         - %s\n",$2}'
  else
    ok "En échec" "aucun"
  fi
  [[ ${VERBOSE} -eq 1 ]] && systemctl list-units --type=service --state=running --no-legend | awk '{printf "         - %s\n",$1}'
else
  warn "systemd" "indisponible"
  command -v service &>/dev/null && service --status-all 2>/dev/null | head -20
fi

# ---------- Réseau ----------
sect "RÉSEAU"
if cmd_exists ip; then
  ip -br addr 2>/dev/null | tail -n +2 | while read -r if st addr rest; do
    printf "  %-16s %-14s %s\n" "$if" "$st" "${addr%%/*}"
  done
else
  row "Interfaces" "commande ip absente"
fi
row "Passerelle" "$(ip route 2>/dev/null | awk '/default/{print $3; exit}')"
row "DNS" "$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd, -)"
if cmd_exists ss; then
  listen=$(ss -tulnH 2>/dev/null | wc -l)
  row "Ports en écoute" "$listen"
  [[ ${VERBOSE} -eq 1 ]] && ss -tulnpH 2>/dev/null | awk '{printf "         - %s %s\n",$5,$7}' | head -30
fi
# règles pare-feu
if cmd_exists firewall-cmd && firewall-cmd --state &>/dev/null; then
  row "Pare-feu" "firewalld ($(firewall-cmd --list-all 2>/dev/null | grep -c services) services, zones: $(firewall-cmd --get-active-zones 2>/dev/null | head -1))"
elif cmd_exists ufw; then
  row "Pare-feu" "UFW : $(ufw status 2>/dev/null | head -1)"
elif cmd_exists iptables && is_root; then
  row "Pare-feu" "iptables : $(iptables -L -n 2>/dev/null | grep -c '^') règles"
else
  warn "Pare-feu" "non détecté ou accès refusé"
fi

# ---------- Utilisateurs ----------
sect "UTILISATEURS"
row "Connectés" "$(who 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, -)"
row "UID 0 (root)" "$(awk -F: '$3==0{print $1}' /etc/passwd | paste -sd, -)"
row "Sudo/Admin" "$(awk -F: '/^(sudo|wheel|admin)/{gsub(",","\n",$4); print $4}' /etc/group | sort -u | paste -sd, -)"
row "Comptes shell" "$(awk -F: '$7!~/(nologin|false|sync|halt|shutdown)/{print $1}' /etc/passwd | wc -l) compte(s) avec shell"
[[ ${VERBOSE} -eq 1 ]] && { echo "  Comptes avec shell :"; awk -F: '$7!~/(nologin|false)/{printf "         - %-12s %s\n",$1,$6}' /etc/passwd; }

# ---------- Cron ----------
sect "TÂCHES PLANIFIÉES"
cron_count=0
for u in $(awk -F: '$7!~/(nologin|false)/{print $1}' /etc/passwd); do
  c=$(crontab -u "$u" -l 2>/dev/null | grep -vc '^\s*#'); cron_count=$((cron_count + c))
done
sys_cron=$(ls /etc/cron.d/ 2>/dev/null | wc -l)
row "Crontabs utilisateurs" "$cron_count entrée(s)"
row "/etc/cron.d" "$sys_cron fichier(s)"

# ---------- Sécurité ----------
sect "SÉCURITÉ"
lastlog=$(last -n 5 --time-format short 2>/dev/null | head -5)
if [[ -n $lastlog ]]; then
  echo "$lastlog" | sed 's/^/         /'
else
  row "Dernières connexions" "indisponible"
fi
if is_root; then
  failed=$(lastb -n 20 2>/dev/null | grep -c .)
  if [[ $failed -gt 0 ]]; then warn "Connexions échouées" "$failed tentative(s) récente(s)"
  else ok "Connexions échouées" "aucune"; fi
else
  row "Connexions échouées" "(root requis pour lastb)"
fi
setuid_n=$(find /usr -perm -4000 -type f 2>/dev/null | wc -l)
row "Binaires setuid" "$setuid_n"
if cmd_exists journalctl && journalctl -p err -S today &>/dev/null; then
  errs=$(journalctl -p err -S today --no-pager 2>/dev/null | grep -c '^[A-Z]')
  if [[ $errs -gt 0 ]]; then warn "Erreurs logs (jour)" "$errs entrée(s)"
  else ok "Erreurs logs (jour)" "aucune"; fi
fi
[[ ${VERBOSE} -eq 1 && -x /usr/bin/needs-restarting ]] && row "Reboot requis" "$(/usr/bin/needs-restarting -r 2>/dev/null | tail -1)"

# ---------- processus top mémoire ----------
if [[ ${VERBOSE} -eq 1 ]]; then
  sect "TOP PROCESSUS (mémoire)"
  ps aux --sort=-%mem | awk 'NR<=6 && NR>1 {printf "  %-8s %5s%% %5s%%  %s\n",$1,$3,$4,substr($0,index($0,$11),60)}'
fi

printf "\n"
sep
printf "  ${C_dim}Rapport généré en mode $([[ $VERBOSE -eq 1 ]] && echo 'verbeux' || echo 'résumé'). Relancez avec -v pour plus de détails.${R}\n\n"