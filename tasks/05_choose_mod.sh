if [ "$NON_INTERACTIVE" -eq 0 ]; then
  read -rp "Darkness Falls Mod installieren? (j/N): " ans
  INSTALL_DARKNESS_FALLS=0
  [[ "$ans" =~ ^[Jj] ]] && INSTALL_DARKNESS_FALLS=1
fi
