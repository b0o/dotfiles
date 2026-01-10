final: prev: {
  charles-niri-fix = prev.charles.overrideAttrs (oldAttrs: {
    pname = "charles-niri-fix";
    postFixup = ''
      ${oldAttrs.postFixup or ""}
      # Wrap with Wayland compatibility and font rendering fixes
      wrapProgram $out/bin/charles \
        --set _JAVA_AWT_WM_NONREPARENTING 1 \
        --set _JAVA_OPTIONS "-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true"
    '';
  });
}
