#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTIÓN DE PROXY SQUID - VERSIÓN FINAL CORREGIDA
# ==============================================================================

# --- COLORES ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Sin color

# --- FUNCIÓN: INFORMACIÓN DE RED Y ESTADO ---
mostrar_info() {
    clear
    echo -e "${BLUE}======================================================"
    echo -e "       SISTEMA DE GESTIÓN DE PROXY (SQUID)"
    echo -e "======================================================"
    echo -e "${NC}FECHA ACTUAL: $(date)"
    echo -e "DATOS DE RED (Tu IP es: 192.168.1.31):"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | sed 's/^/  - /'
    
    echo -e "\nESTADO DEL SERVICIO:"
    if systemctl is-active --quiet squid; then
        echo -e "  Status: ${GREEN}ACTIVO${NC}"
    else
        echo -e "  Status: ${RED}INACTIVO / NO INSTALADO${NC}"
    fi
    echo -e "${BLUE}======================================================${NC}"
}

# --- FUNCIÓN: CONSULTA DE LOGS ---
consultar_logs() {
    if [ ! -f /var/log/squid/access.log ]; then
        echo -e "${RED}ERROR: El archivo de log no existe. Instala y arranca Squid primero.${NC}"
    else
        echo -e "\n--- CONSULTA DE LOGS ---"
        echo "1. Ver últimos 20 movimientos"
        echo "2. Filtrar por fecha (hoy)"
        echo "3. Filtrar por tipo (escriba TCP_MISS)"
        read -p "Opción: " log_opt
        case "$log_opt" in
            1) sudo tail -n 20 /var/log/squid/access.log ;;
            2) sudo grep "$(date +%d/%b/%Y)" /var/log/squid/access.log ;;
            3) read -p "Tipo de log a buscar: " tipo && sudo grep "$tipo" /var/log/squid/access.log ;;
        esac
    fi
    read -p "Presiona Enter para continuar..."
}

# --- FUNCIÓN: GENERAR TRÁFICO DE PRUEBA (OPCIÓN 7) ---
generar_trafico_prueba() {
    echo -e "\n${BLUE}Generando petición de prueba a Google vía Proxy...${NC}"
    # -x indica el proxy, -I pide cabeceras para no descargar toda la web
    curl -x http://127.0.0.1:3128 -I http://www.google.com > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}¡Petición enviada con éxito! Revisa los logs ahora.${NC}"
    else
        echo -e "${RED}Error: No se pudo conectar. ¿Está el servicio activo?${NC}"
    fi
    read -p "Presiona Enter para continuar..."
}

# --- LÓGICA DE PARÁMETROS (EJECUCIÓN DIRECTA) ---
if [ $# -gt 0 ]; then
    case "$1" in
        --install) sudo apt update && sudo apt install -y squid ;;
        --ansible) ansible-playbook install_proxy.yml ;;
        --docker)  docker build -t proxy-ubuntu . && docker run -d -p 3128:3128 proxy-ubuntu ;;
        --start)   sudo systemctl start squid ;;
        --stop)    sudo systemctl stop squid ;;
        --remove)  sudo apt purge -y squid ;;
        --test)    generar_trafico_prueba ;;
        *) echo "Uso: $0 {--install|--ansible|--docker|--start|--stop|--remove|--test}" ;;
    esac
    exit 0
fi

# --- MENÚ PRINCIPAL (BUCLE) ---
while true; do
    mostrar_info
    echo -e "${BLUE}1.${NC} INSTALACIÓN"
    echo -e "${BLUE}2.${NC} ELIMINACIÓN DEL SERVICIO"
    echo -e "${BLUE}3.${NC} PUESTA EN MARCHA (Start)"
    echo -e "${BLUE}4.${NC} PARADA (Stop)"
    echo -e "${BLUE}5.${NC} CONSULTAR LOGS"
    echo -e "${BLUE}6.${NC} EDITAR CONFIGURACIÓN (squid.conf)"
    echo -e "${BLUE}7.${NC} GENERAR TRÁFICO DE PRUEBA (Auto-Log)"
    echo -e "${BLUE}0.${NC} SALIR"

    echo -ne "\n${GREEN}Seleccione una opción: ${NC}"
    read opcion

    case "$opcion" in
        1)
            echo -e "\nElija método de instalación:"
            echo "a) Comandos estándar (apt)"
            echo "b) Ansible Playbook"
            echo "c) Docker Container"
            read -p "Sub-opción: " met
            case "$met" in
                a) sudo apt update && sudo apt install -y squid ;;
                b) ansible-playbook install_proxy.yml ;;
                c) docker build -t proxy-ubuntu . && docker run -d -p 3128:3128 proxy-ubuntu ;;
                *) echo "Método no válido" ;;
            esac
            ;;
        2)
            sudo apt purge -y squid && sudo apt autoremove -y
            echo "Servicio eliminado."
            ;;
        3)
            sudo systemctl start squid && echo -e "${GREEN}Servicio iniciado.${NC}"
            ;;
        4)
            sudo systemctl stop squid && echo -e "${RED}Servicio detenido.${NC}"
            ;;
        5)
            consultar_logs
            ;;
        6)
            sudo nano /etc/squid/squid.conf
            ;;
        7)
            generar_trafico_prueba
            ;;
        0)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo -e "${RED}Opción no válida ($opcion). Intenta de nuevo.${NC}"
            ;;
    esac
    sleep 1
done
