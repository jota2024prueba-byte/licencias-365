import streamlit as st
import pandas as pd

# ==============================================
# CONFIGURACIÓN
# ==============================================
GOOGLE_SHEET_ID = "1O3fjQBNkTR0I7c28xTXkVRr8Szs_-YH9S0o149mLsa4/edit?gid=0#gid=0"
SHEET_NAME = "365"

USUARIOS = {
      "alfonso.gomez": "Alf2026*+*",
    "jorge.cantillo": "Jolucaro*+*",
    "cristian.vicioso": "Vic26*+*",
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
        df = pd.read_csv(
            url,
            on_bad_lines="skip",
            engine="python"
        )
        df.columns = df.columns.str.strip()
        df.columns = df.columns.str.upper()
        return df
    except Exception as e:
        st.error(f"Error: {e}")
        return None

df = cargar_datos()

# --- DIAGNÓSTICO DE COLUMNAS ---
st.write("📋 Columnas detectadas:", list(df.columns) if df is not None else "Sin datos")

# --- INTERFAZ PRINCIPAL ---
st.title("📋 Consulta Licencias 365")
st.caption(f"👤 Conectado: {st.session_state.usuario}")
st.markdown("---")

if df is not None:
    col_dep = "DEPENDENCIA"
    col_usu = "USUARIO"
    col_cod = "CODIGO DE ACTIVO"
    col_ser = "SERIAL"
    col_pc = "COMPUTADOR"
    col_lic = "LICENCIA"
    
    busqueda = st.text_input("🔍 Buscar: código, serial, equipo o correo")
    
    dep_val = st.selectbox("Filtrar por Dependencia", ["Todas"] + sorted(df[col_dep].dropna().unique().tolist()))
    usu_val = st.selectbox("Filtrar por Usuario", ["Todos"] + sorted(df[col_usu].dropna().unique().tolist()))
    
    res = df.copy()
    if busqueda:
        filtro = False
        for c in [col_cod, col_ser, col_pc, col_usu, col_dep]:
            filtro |= res[c].astype(str).str.contains(busqueda, case=False, na=False)
        res = res[filtro]
    if dep_val != "Todas":
        res = res[res[col_dep] == dep_val]
    if usu_val != "Todos":
        res = res[res[col_usu] == usu_val]
    
    st.info(f"✅ {len(res)} equipos encontrados")
    
    if len(res) == 1:
        eq = res.iloc[0]
        st.success("### 📌 Datos del Equipo")
        st.markdown(f"""
        | Campo | Información |
        |---|---|
        | 🏢 Dependencia | **{eq[col_dep]}** |
        | 💻 Equipo | {eq[col_pc]} |
        | 🔢 Serial | `{eq[col_ser]}` |
        | 🏷️ Código Activo | `{eq[col_cod]}` |
        | 📧 Usuario/Licencia | `{eq[col_usu]}` |
        | 📄 Tipo Licencia | {eq[col_lic]} |
        """)
    else:
        for _, eq in res.iterrows():
            st.markdown(f"**{eq[col_pc]}** · `{eq[col_cod]}` · {eq[col_usu]}")
            st.divider()
    
    st.download_button("📥 Descargar CSV", res.to_csv(index=False).encode("utf-8"), "licencias.csv", "text/csv")

if st.button("Cerrar sesión"):
    del st.session_state.usuario
    st.rerun()