const rgui = @import("raygui");

pub const font_size = 10;
pub const input_field_height = font_size * 3;

pub const Toolbar = struct {
    pub const height = 30;
    pub const button_dim = 20;
    pub const button_padding = (height - button_dim) / 2;

    pub const popup_width = 500;
    pub const popup_height = 350;
    pub const popup_text_padding = 10;
    pub const popup_alpha = 0.7;

    pub const file_save_icon = rgui.IconName.file_open;
    pub const file_load_icon = rgui.IconName.file_save;
};

pub const EntityList = struct {
    pub const spacing = 15;
    pub const y_base_position = 80;
    pub const width = 170;
    pub const entity_entry_padding = 20;
    pub const button_dim = 20;
};

pub const EntityInspector = struct {
    pub const spacing = 15;
    pub const y_base_position = 80;
    pub const component_field_width_padding = 10;
    pub const width = 300;
    pub const button_dim = 20;
    pub const checkbox_dim = 20;
};
