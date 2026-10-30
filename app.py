import streamlit as st
import pandas as pd

# ==============================================
GOOGLE_SHEET_ID = "1O3fjQBNkTR0I7c28xTXkVRr8Szs_-YH9S0o149mLsa4/edit?gid=0#gid=0"
SHEET_NAME = "365"

USUARIOS = {
    "alfonso.gomez": "Alf2026*+*",
    "jorge.cantillo": "Jolucaro*+*,
   
    
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
        df.columns = df.columns.str.strip()  # Borra espacios sobrantes en los nombres
        return df
    except Exception as e:
        st.error(f"Error: {e}")
        return None

df = cargar_datos()

# --- DIAGNÓSTICO: MUESTRA LOS NOMBRES REALES DE LAS COLUMNAS ---
st.write("📋 Columnas encontradas en tu hoja:")
st.write(list(df.columns))  # 👈 Aquí verás cómo se llaman de verdad

# --- INTERFAZ PRINCIPAL ---
st.title("📋 Consulta Licencias 365")
st.caption(f"👤 Conectado: {st.session_state.usuario}")
st.markdown("---")

if df is not None:
    # Reemplaza los nombres abajo por los que veas en la lista de arriba
    col_dependencia = "DEPENDENCIA"
    col_usuario = "USUARIO"
    col_activo = "CODIGO DE ACTIVO"
    col_serial = "SERIAL"
    col_equipo = "COMPUTADOR"
    col_licencia = "LICENCIA"
    
    busqueda = st.text_input("🔍 Buscar: código, serial, equipo o correo", 
                              placeholder="Ej: 0525196081528050")
    
    dep = st.selectbox("Filtrar por Dependencia", ["Todas"] + sorted(df[col_dependencia].dropna().unique().tolist()))
    usu = st.selectbox("Filtrar por Usuario", ["Todos"] + sorted(df[col_usuario].dropna().unique().tolist()))
    
    res = df.copy()
    if busqueda:
        filtro = False
        for col in [col_activo, col_serial, col_equipo, col_usuario, col_dependencia]:
            filtro |= res[col].astype(str).str.contains(busqueda, case=False, na=False)
        res = res[filtro]
    if dep != "Todas":
        res = res[res[col_dependencia] == dep]
    if usu != "Todos":
        res = res[res[col_usuario] == usu]
    
    st.info(f"✅ {len(res)} equipos encontrados")
    
    if len(res) == 1:
        eq = res.iloc[0]
        st.success("### 📌 Datos del Equipo")
        st.markdown(f"""
        | Campo | Información |
        |---|---|
        | 🏢 Dependencia | **{eq[col_dependencia]}** |
        | 💻 Equipo | {eq[col_equipo]} |
        | 🔢 Serial | `{eq[col_serial]}` |
        | 🏷️ Código Activo | `{eq[col_activo]}` |
        | 📧 Usuario/Licencia | `{eq[col_usuario]}` |
        | 📄 Tipo Licencia | {eq[col_licencia]} |
        """)
    else:
        for _, eq in res.iterrows():
            st.markdown(f"**{eq[col_equipo]}** · `{eq[col_activo]}` · {eq[col_usuario]}")
            st.divider()
    
    st.download_button("📥 Descargar CSV", res.to_csv(index=False).encode("utf-8"), "licencias.csv", "text/csv")

if st.button("Cerrar sesión"):
    del st.session_state.usuario
    st.rerun()
