import streamlit as st
import pandas as pd

# ==============================================
GOOGLE_SHEET_ID = "1O3fjQBNkTR0I7c28xTXkVRr8Szs_-YH9S0o149mLsa4/edit?gid=0#gid=0"
SHEET_NAME = "365"

USUARIOS = {
    "cristian.vicioso": "Vic26***",
    "alfonso.gomez": "cajamag2026"
    "jorge.cantillo": "Jolucaro*+*",
}
# ==============================================

st.set_page_config(page_title="Licencias 365", page_icon="💻", layout="wide")

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

@st.cache_data(ttl=60)
def cargar_datos():
    url = f"https://docs.google.com/spreadsheets/d/{GOOGLE_SHEET_ID}/gviz/tq?tqx=out:csv&sheet={SHEET_NAME}"
    try:
        df = pd.read_csv(url, on_bad_lines="skip", engine="python")
        df.columns = df.columns.str.strip().str.upper()
        return df
    except Exception as e:
        st.error(f"Error: {e}")
        return None

df = cargar_datos()
st.write("📋 Columnas detectadas:", list(df.columns) if df is not None else "Sin datos")

st.title("📋 Consulta Licencias 365")
st.caption(f"👤 Conectado: {st.session_state.usuario}")
st.markdown("---")

if df is not None:
    dep = "DEPENDENCIA"
    usu = "USUARIO"
    cod = "CODIGO DE ACTIVO"
    ser = "SERIAL"
    pc = "COMPUTADOR"
    lic = "LICENCIA"
    
    bus = st.text_input("🔍 Buscar: código, serial, equipo o correo")
    fil_dep = st.selectbox("Filtrar por Dependencia", ["Todas"] + sorted(df[dep].dropna().unique().tolist()))
    fil_usu = st.selectbox("Filtrar por Usuario", ["Todos"] + sorted(df[usu].dropna().unique().tolist()))
    
    res = df.copy()
    if bus:
        filtro = False
        for c in [cod, ser, pc, usu, dep]:
            filtro |= res[c].astype(str).str.contains(bus, case=False, na=False)
        res = res[filtro]
    if fil_dep != "Todas": res = res[res[dep] == fil_dep]
    if fil_usu != "Todos": res = res[res[usu] == fil_usu]
    
    st.info(f"✅ {len(res)} equipos encontrados")
    if len(res) == 1:
        eq = res.iloc[0]
        st.success("### 📌 Datos del Equipo")
        st.markdown(f"""
        | Campo | Información |
        |---|---|
        | 🏢 Dependencia | **{eq[dep]}** |
        | 💻 Equipo | {eq[pc]} |
        | 🔢 Serial | `{eq[ser]}` |
        | 🏷️ Código Activo | `{eq[cod]}` |
        | 📧 Usuario | `{eq[usu]}` |
        | 📄 Licencia | {eq[lic]} |
        """)
    else:
        for _, eq in res.iterrows():
            st.markdown(f"**{eq[pc]}** · `{eq[cod]}` · {eq[usu]}")
            st.divider()
    
    st.download_button("📥 Descargar CSV", res.to_csv(index=False).encode("utf-8"), "licencias.csv", "text/csv")

if st.button("Cerrar sesión"):
    del st.session_state.usuario
    st.rerun()