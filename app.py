import streamlit as st
import pandas as pd

GOOGLE_SHEET_ID = "1O3fjQBNkTR0I7c28xTXkVRr8Szs_-YH9S0o149mLsa4/edit?pli=1&gid=0#gid=0"
SHEET_NAME = "365"

USUARIOS = {
    "cristian.vicioso": "Vic26*+*",
    "alfonso.gomez": "Poncho26*+*",
    "jorge.cantillo": "Joca2026*+*"
}

st.set_page_config(page_title="Licencias 365", page_icon="💻", layout="wide")

if "usuario" not in st.session_state:
    st.title("🔐 Acceso Restringido")
    u = st.text_input("Usuario")
    p = st.text_input("Contraseña", type="password")
    if st.button("Ingresar"):
        if u in USUARIOS and p == USUARIOS[u]:
            st.session_state.usuario = u
            st.rerun()
        else:
            st.error("❌ Datos incorrectos")
    st.stop()

@st.cache_data(ttl=60)
def cargar():
    url = f"https://docs.google.com/spreadsheets/d/{GOOGLE_SHEET_ID}/gviz/tq?tqx=out:csv&sheet={SHEET_NAME}"
    try:
        df = pd.read_csv(url, on_bad_lines="skip", engine="python")
        df.columns = df.columns.str.strip()
        st.write("📋 Nombres de columnas:", list(df.columns))
        return df
    except Exception as e:
        st.error(f"Error: {e}")
        return None

df = cargar()
st.title("📋 Consulta Licencias 365")
st.caption(f"👤 Conectado: {st.session_state.usuario}")
st.markdown("---")

if df is not None:
    st.subheader("🔍 Verificación de columnas")
    todas_bien = True
    
    if "DEPENDENCIA" not in df.columns:
        st.error("❌ No encontré: DEPENDENCIA")
        todas_bien = False
    if "USUARIO" not in df.columns:
        st.warning("⚠️ No encontré: USUARIO")
        todas_bien = False
    if "CODIGO DE ACTIVO" not in df.columns:
        st.warning("⚠️ No encontré: CODIGO DE ACTIVO")
        todas_bien = False
    if "SERIAL" not in df.columns:
        st.warning("⚠️ No encontré: SERIAL")
        todas_bien = False
    if "COMPUTADOR" not in df.columns:
        st.warning("⚠️ No encontré: COMPUTADOR")
        todas_bien = False
    if "LICENCIA" not in df.columns:
        st.warning("⚠️ No encontré: LICENCIA")
        todas_bien = False

    if todas_bien:
        st.success("✅ Todas las columnas están bien")
        
        col_dep = "DEPENDENCIA"
        col_usu = "USUARIO"
        col_cod = "CODIGO DE ACTIVO"
        col_ser = "SERIAL"
        col_pc = "COMPUTADOR"
        col_lic = "LICENCIA"

        bus = st.text_input("🔍 Buscar: código, serial, equipo o correo")
        dep_sel = st.selectbox("Filtrar por Dependencia", ["Todas"] + sorted(df[col_dep].dropna().unique().tolist()))
        usu_sel = st.selectbox("Filtrar por Usuario", ["Todos"] + sorted(df[col_usu].dropna().unique().tolist()))

        res = df.copy()
        if bus:
            filtro = False
            for c in [col_cod, col_ser, col_pc, col_usu, col_dep]:
                filtro |= res[c].astype(str).str.contains(bus, case=False, na=False)
            res = res[filtro]
        if dep_sel != "Todas":
            res = res[res[col_dep] == dep_sel]
        if usu_sel != "Todos":
            res = res[res[col_usu] == usu_sel]

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
            | 📧 Usuario | `{eq[col_usu]}` |
            | 📄 Licencia | {eq[col_lic]} |
            """)
        else:
            for _, eq in res.iterrows():
                st.markdown(f"**{eq[col_pc]}** · `{eq[col_cod]}` · {eq[col_usu]}")
                st.divider()

        st.download_button("📥 Descargar CSV", res.to_csv(index=False).encode("utf-8"), "licencias.csv", "text/csv")

if st.button("Cerrar sesión"):
    del st.session_state.usuario
    st.rerun()
