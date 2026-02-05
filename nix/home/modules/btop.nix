# Btop system monitor configuration
_: {
  lavi.btop.enable = true;

  programs.btop = {
    enable = true;

    settings = {
      theme_background = false;
      vim_keys = true;
      rounded_corners = false;
      shown_boxes = "proc cpu mem net gpu0";
      update_ms = 500;
      proc_sorting = "cpu direct";
      proc_tree = true;
      proc_gradient = false;
      proc_aggregate = true;
      cpu_bottom = true;
      temp_scale = "fahrenheit";
      mem_below_net = true;
      show_battery = false;

      # Config managed by home-manager, don't overwrite
      save_config_on_exit = false;
    };
  };
}
