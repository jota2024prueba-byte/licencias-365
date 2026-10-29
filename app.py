import streamlit as st
import pandas as pd

# ==============================================
# CONFIGURACIÓN - MODIFICA ESTOS DATOS AQUÍ
# ==============================================
GOOGLE_SHEET_ID = "https://docs.google.com/spreadsheets/d/1I2TY7QoF9mFqzYoNFEGrMjMpnNYZv6NUuusTvGPa09s/edit?gid=0#gid=0"
SHEET_NAME = "365"

# 5 USUARIOS PERMITIDOS - Puedes cambiar usuarios y claves
USUARIOS = {
    "cristian.vicioso": "Cris2026*+*",
   "alfonso.gomez": "Alf2026*+*",
    "jorge.cantillo": "Jolucaro*+*",
}
# ==============================================

st.set_page_config(page_title="Licencias 365", page_icon="💻", layout="wide")

# --- LOGIN ---
if "usuario" not in st.session_state:
    st.title("🔐 Acceso Restringido")
    user = st.text_input("Usuario")
    pwd = st.text_input("Contraseña", type="password")
    
    if st.button("Ingresar"):
        if user in USUARIOS and pwd == USUARIOS[user]:
            st.session_state.usuario = user
            st.rerun()
        else:
            st.error("❌ Usuario o contraseña incorrectos")
    st.stop()

# --- CARGA DE DATOS ---
@st.cache_data(ttl=60)
def cargar_datos():
    url = f"https://docs.google.com/spreadsheets/d/{GOOGLE_SHEET_ID}/gviz/tq?tqx=out:csv&sheet={SHEET_NAME}"
    try:
        df = pd.read_csv(url)
        df.columns = df.columns.str.strip()
        return df
    except Exception as e:
        st.error(f"Error: {e}")
        return None

df = cargar_datos()

# --- INTERFAZ PRINCIPAL ---
st.title("📋 Consulta Licencias 365")
st.caption(f"👤 Conectado: {st.session_state.usuario}")
st.markdown("---")

if df is not None:
    busqueda = st.text_input("🔍 Buscar: código, serial, equipo o correo", 
                              placeholder="Ej: 0525196081528050 o 4CE546CP4R")
    
    dep = st.selectbox("Filtrar por Dependencia", ["Todas"] + sorted(df["DEPENDENCIA"].dropna().unique().tolist()))
    usu = st.selectbox("Filtrar por Usuario", ["Todos"] + sorted(df["USUARIO"].dropna().unique().tolist()))
    
    # Aplicar filtros
    res = df.copy()
    if busqueda:
        filtro = False
        for col in ["CODIGO DE ACTIVO", "SERIAL", "COMPUTADOR", "USUARIO", "DEPENDENCIA"]:
            filtro |= res[col].astype(str).str.contains(busqueda, case=False, na=False)
        res = res[filtro]
    if dep != "Todas": res = res[res["DEPENDENCIA"] == dep]
    if usu != "Todos": res = res[res["USUARIO"] == usu]
    
    st.info(f"✅ {len(res)} equipos encontrados")
    
    if len(res) == 1:
        eq = res.iloc[0]
        st.success("### 📌 Datos del Equipo")
        st.markdown(f"""
        | Campo | Información |
        |---|---|
        | 🏢 Dependencia | **{eq['DEPENDENCIA']}** |
        | 💻 Equipo | {eq['COMPUTADOR']} |
        | 🔢 Serial | `{eq['SERIAL']}` |
        | 🏷️ Código Activo | `{eq['CODIGO DE ACTIVO']}` |
        | 📧 Usuario/Licencia | `{eq['USUARIO']}` |
        | 📄 Tipo Licencia | {eq['LICENCIA']} |
        """)
    else:
        for _, eq in res.iterrows():
            st.markdown(f"**{eq['COMPUTADOR']}** · `{eq['CODIGO DE ACTIVO']}` · {eq['USUARIO']}")
            st.divider()
    
    st.download_button("📥 Descargar CSV", res.to_csv(index=False).encode("utf-8"), "licencias.csv", "text/csv")

if st.button("Cerrar sesión"):
    del st.session_state.usuario
    st.rerun()
