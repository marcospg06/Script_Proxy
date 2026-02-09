#!/bin/bash

# ==============================================================================
# SCRIPT DE GESTIÓN DE PROXY SQUID - VERSIÓN FINAL CON DOCKER
# ==============================================================================

# --- COLORES ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# --- FUNCIÓN: INFORMACIÓN DE RED Y ESTADO ---
mostrar_info() {
    clear
    IP_LOCAL=$(hostname -I | awk '{print $1}')

    echo -e "${BLUE}======================================================"
    echo -e "       SISTEMA DE GESTIÓN DE PROXY (SQUID)"
    echo -e "======================================================"
    echo -e "${NC}FECHA ACTUAL: $(date)"
    echo -e "DATOS DE RED (Tu IP es: $IP_LOCAL):"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | sed 's/^/  - /'

    echo -e "\nESTADO DEL SERVICIO:"
    if systemctl is-active --quiet squid 2>/dev/null; then
        echo -e "  Status: ${GREEN}ACTIVO (Sistema)${NC}"
    elif docker ps --format '{{.Names}}' | grep -q "^squid$" 2>/dev/null; then
        echo -e "  Status: ${GREEN}ACTIVO (Docker)${NC}"
        echo "  Contenedor Squid en ejecución:"
        sudo docker ps | grep squid
    else
        echo -e "  Status: ${RED}INACTIVO / NO INSTALADO${NC}"
    fi

    echo -e "${BLUE}======================================================${NC}"
}

# --- FUNCIÓN: CONSULTA DE LOGS ---
consultar_logs() {
    LOG_SYS="/var/log/squid/access.log"
    LOG_DOCKER="/opt/squid-docker/logs/access.log"

    if [ -f "$LOG_SYS" ]; then
        LOG="$LOG_SYS"
    elif [ -f "$LOG_DOCKER" ]; then
        LOG="$LOG_DOCKER"
    else
        echo -e "${RED}No se encontraron logs de Squid.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    echo -e "\n--- CONSULTA DE LOGS ---"
    echo "1. Ver últimos 20 movimientos"
    echo "2. Filtrar por fecha (hoy)"
    echo "3. Filtrar por tipo (ej. TCP_MISS)"
    read -p "Opción: " log_opt

    case "$log_opt" in
        1) sudo tail -n 20 "$LOG" ;;
        2) sudo grep "$(date +%d/%b/%Y)" "$LOG" ;;
        3) read -p "Tipo de log: " tipo && sudo grep "$tipo" "$LOG" ;;
        *) echo "Opción no válida" ;;
    esac

    read -p "Presiona Enter para continuar..."
}

# --- FUNCIÓN: GENERAR TRÁFICO DE PRUEBA ---
generar_trafico_prueba() {
    echo -e "\n${BLUE}Generando petición de prueba vía Proxy...${NC}"
    curl -x http://127.0.0.1:3128 -I http://www.google.com > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Petición enviada con éxito. Revisa los logs.${NC}"
    else
        echo -e "${RED}Error: no se pudo conectar al proxy.${NC}"
    fi

    read -p "Presiona Enter para continuar..."
}

# --- MENÚ PRINCIPAL ---
while true; do
    mostrar_info

    echo -e "${BLUE}1.${NC} INSTALACIÓN"
    echo -e "${BLUE}2.${NC} ELIMINACIÓN DEL SERVICIO"
    echo -e "${BLUE}3.${NC} PUESTA EN MARCHA (Start)"
    echo -e "${BLUE}4.${NC} PARADA (Stop)"
    echo -e "${BLUE}5.${NC} CONSULTAR LOGS"
    echo -e "${BLUE}6.${NC} EDITAR CONFIGURACIÓN (squid.conf)"
    echo -e "${BLUE}7.${NC} GENERAR TRÁFICO DE PRUEBA"
    echo -e "${BLUE}8.${NC} LISTAR CONTENEDORES DOCKER"
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
                a)
                    sudo apt update && sudo apt install -y squid
                ;;
                b)
                    ansible-playbook install_proxy.yml
                ;;
                c)
                    echo -e "${BLUE}Instalando Squid mediante Docker...${NC}"

                    # --- COMPROBAR E INSTALAR DOCKER ---
                    if ! command -v docker >/dev/null; then
                        echo -e "${RED}Docker no está instalado. Instalando...${NC}"
                        sudo apt update
                        sudo apt install -y docker.io
                    fi

                    # --- COMPROBAR SI EL SERVICIO DOCKER ESTÁ ACTIVO ---
                    if ! systemctl is-active --quiet docker; then
                        echo -e "${BLUE}Iniciando servicio Docker...${NC}"
                        sudo systemctl enable --now docker
                    fi

                    # --- CONFIGURAR CARPETAS Y PERMISOS ---
                    sudo mkdir -p /opt/squid-docker/logs
                    sudo chown -R $USER:$USER /opt/squid-docker

                    # --- CREAR squid.conf SI NO EXISTE ---
                    if [ ! -f /opt/squid-docker/squid.conf ]; then
                        sudo tee /opt/squid-docker/squid.conf > /dev/null <<EOF
http_port 3128
acl localnet src 0.0.0.0/0
http_access allow localnet
http_access deny all
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF
                    fi

                    # --- ELIMINAR CONTENEDOR ANTIGUO SI EXISTE ---
                    if docker ps -a --format '{{.Names}}' | grep -q "^squid$"; then
                        sudo docker rm -f squid
                    fi

                    # --- LANZAR CONTENEDOR SQUID ---
                    sudo docker run -d \
                      --name squid \
                      -p 3128:3128 \
                      -v /opt/squid-docker/squid.conf:/etc/squid/squid.conf \
                      -v /opt/squid-docker/logs:/var/log/squid \
                      --restart unless-stopped \
                      sameersbn/squid

                    echo -e "${GREEN}Squid desplegado en Docker correctamente.${NC}"
                    read -p "Pulsa ENTER para continuar..."
		;;

		*)
                    echo -e "${RED}Método no válido${NC}"
		;;
		esac
	;;
        2)
            sudo apt purge -y squid && sudo apt autoremove -y
            sudo docker rm -f squid 2>/dev/null
            echo "Servicio eliminado."
	;;
        3)
            # --- START SOLO CON EL MÉTODO DISPONIBLE ---
            if systemctl is-active --quiet squid 2>/dev/null; then
                sudo systemctl start squid
            else
                sudo docker start squid
            fi
	;;
        4)
            if systemctl is-active --quiet squid 2>/dev/null; then
                sudo systemctl stop squid
            else
                sudo docker stop squid
            fi
	;;
        5)
            consultar_logs
	;;
        6)
            sudo nano /etc/squid/squid.conf
	    # Si Squid está instalado en el sistema
	    if systemctl is-active --quiet squid 2>/dev/null || systemctl list-unit-files | grep -q squid.service; then
	        echo -e "${BLUE}Editando configuración de Squid (Sistema)...${NC}"
	        sudo nano /etc/squid/squid.conf
	        sudo systemctl restart squid
	        echo -e "${GREEN}Squid reiniciado (Sistema).${NC}"

	    # Si Squid está en Docker
	    elif docker ps -a --format '{{.Names}}' | grep -q "^squid$" 2>/dev/null; then
	        echo -e "${BLUE}Editando configuración de Squid (Docker)...${NC}"
	        sudo nano /opt/squid-docker/squid.conf
	        sudo docker restart squid
	        echo -e "${GREEN}Contenedor Squid reiniciado.${NC}"

	    else
	        echo -e "${RED}Squid no está instalado ni en sistema ni en Docker.${NC}"
	    fi

	    read -p "Presiona Enter para continuar..."
	;;
        7)
            generar_trafico_prueba
	;;
        8)
            echo -e "\n--- Contenedores Docker en ejecución ---"
            sudo docker ps
            read -p "Presiona Enter para continuar..."
	;;
        0)
            echo "Saliendo..."
            exit 0
	;;
        *)
            echo -e "${RED}Opción no válida.${NC}"
	;;
    	esac
    sleep 1
done
