FROM espressif/idf:release-v4.4

WORKDIR /app

ADD . /app

# Apply patches
RUN cd /opt/esp/idf && \
	patch --ignore-whitespace -p1 -i "/app/tools/patches/panic-hook (esp-idf 4).diff" && \
	patch --ignore-whitespace -p1 -i "/app/tools/patches/sdcard-fix (esp-idf 4).diff"

# --- AUTOMATED CODE PATCHES FOR STANDARD T-DECK ---
# 1. Modify config.h: Strip out the T-Deck Plus hardware pin map and insert Standard I2C configuration
RUN sed -i '/#define RG_GAMEPAD_I2C_MAP/,/}/c\#define RG_TARGET_STANDARD_T_DECK 1\n#define RG_GAMEPAD_DRIVER 0\n#define T_DECK_STANDARD_KEYBOARD 1' /app/components/retro-go/targets/t-deck-plus/config.h

# 2. Modify rg_input.c: Insert the v4.4-compatible I2C reading logic inside rg_input_read_gamepad
RUN sed -i '/uint32_t rg_input_read_gamepad(void)/,/return gamepad_state;/c\uint32_t rg_input_read_gamepad(void)\n{\n#ifdef RG_TARGET_SDL2\n    SDL_PumpEvents();\n#endif\n#if defined(RG_TARGET_STANDARD_T_DECK)\n    uint8_t i2c_buffer[8] = {0};\n    uint8_t raw_cmd = T_DECK_KBD_MODE_RAW_CMD;\n    i2c_cmd_handle_t cmd = i2c_cmd_link_create();\n    i2c_master_start(cmd);\n    i2c_master_write_byte(cmd, (T_DECK_KBD_ADDRESS << 1) | I2C_MASTER_WRITE, true);\n    i2c_master_write_byte(cmd, raw_cmd, true);\n    i2c_master_start(cmd);\n    i2c_master_write_byte(cmd, (T_DECK_KBD_ADDRESS << 1) | I2C_MASTER_READ, true);\n    i2c_master_read(cmd, i2c_buffer, 8, I2C_MASTER_LAST_NACK);\n    i2c_master_stop(cmd);\n    esp_err_t ret = i2c_master_cmd_begin(I2C_NUM_0, cmd, 100 / portTICK_PERIOD_MS);\n    i2c_cmd_link_delete(cmd);\n    if (ret == ESP_OK) {\n        uint32_t standard_state = 0;\n        if (!(i2c_buffer[0] & (1 << 0))) standard_state |= RG_KEY_UP;\n        if (!(i2c_buffer[0] & (1 << 1))) standard_state |= RG_KEY_DOWN;\n        if (!(i2c_buffer[0] & (1 << 2))) standard_state |= RG_KEY_LEFT;\n        if (!(i2c_buffer[0] & (1 << 3))) standard_state |= RG_KEY_RIGHT;\n        if (!(i2c_buffer[0] & (1 << 4))) standard_state |= RG_KEY_A;\n        for (int i = 2; i < 8; i++) {\n            if (i2c_buffer[i] == 0x20) standard_state |= RG_KEY_START;\n            if (i2c_buffer[i] == 0x1B) standard_state |= RG_KEY_MENU;\n            if (i2c_buffer[i] == 101 || i2c_buffer[i] == 69) standard_state |= RG_KEY_B;\n        }\n        gamepad_state = standard_state;\n    }\n#endif\n    return gamepad_state;' /app/components/retro-go/rg_input.c

# 3. Inject missing header to the top of rg_input.c
RUN sed -i '1s/^/#include <driver\/i2c.h>\n/' /app/components/retro-go/rg_input.c
# --------------------------------------------------

# Build og eksporter alle binaries
SHELL ["/bin/bash", "-c"]
RUN . /opt/esp/idf/export.sh && \
	python rg_tool.py --target=t-deck-plus build-img all && \
	mkdir -p /app/dist && \
	cp build/*.bin /app/dist/ 2>/dev/null || true && \
	cp build/t-deck-plus/*.bin /app/dist/ 2>/dev/null || true && \
	cp releases/*.bin /app/dist/ 2>/dev/null || true
