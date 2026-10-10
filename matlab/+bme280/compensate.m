function [T_C, RH_pct, P_kPa] = compensate(raw, cal)
    % COMPENSATE Convert raw BME280 ADC bytes to T [C], RH [%], P [kPa] using the Bosch datasheet compensation formulas.
    %   Part of the 'bme280' package - call as bme280.compensate(...).
    %
    % Parse raw 8-byte data from registers 0xF7-0xFE
    % Bytes: press_msb, press_lsb, press_xlsb, temp_msb, temp_lsb, temp_xlsb, hum_msb, hum_lsb
    adc_P = bitshift(int32(raw(1)), 12) + bitshift(int32(raw(2)), 4) + ...
            bitshift(int32(raw(3)), -4);
    adc_T = bitshift(int32(raw(4)), 12) + bitshift(int32(raw(5)), 4) + ...
            bitshift(int32(raw(6)), -4);
    adc_H = bitshift(int32(raw(7)), 8) + int32(raw(8));

    % Temperature compensation
    var1 = (double(adc_T)/16384.0 - double(cal.dig_T1)/1024.0) * double(cal.dig_T2);
    var2 = ((double(adc_T)/131072.0 - double(cal.dig_T1)/8192.0) * ...
            (double(adc_T)/131072.0 - double(cal.dig_T1)/8192.0)) * double(cal.dig_T3);
    t_fine = var1 + var2;
    T_C = t_fine / 5120.0;

    % Pressure compensation
    var1 = t_fine/2.0 - 64000.0;
    var2 = var1 * var1 * double(cal.dig_P6) / 32768.0;
    var2 = var2 + var1 * double(cal.dig_P5) * 2.0;
    var2 = var2/4.0 + double(cal.dig_P4) * 65536.0;
    var1 = (double(cal.dig_P3) * var1 * var1 / 524288.0 + double(cal.dig_P2) * var1) / 524288.0;
    var1 = (1.0 + var1/32768.0) * double(cal.dig_P1);
    if var1 == 0
        P_kPa = 0;
    else
        p = 1048576.0 - double(adc_P);
        p = (p - var2/4096.0) * 6250.0 / var1;
        var1 = double(cal.dig_P9) * p * p / 2147483648.0;
        var2 = p * double(cal.dig_P8) / 32768.0;
        p = p + (var1 + var2 + double(cal.dig_P7)) / 16.0;
        P_kPa = p / 1000.0;  % Convert Pa to kPa
    end

    % Humidity compensation
    h = t_fine - 76800.0;
    if h == 0
        RH_pct = 0;
    else
        h = (double(adc_H) - (double(cal.dig_H4) * 64.0 + double(cal.dig_H5) / 16384.0 * h)) * ...
            (double(cal.dig_H2) / 65536.0 * (1.0 + double(cal.dig_H6) / 67108864.0 * h * ...
            (1.0 + double(cal.dig_H3) / 67108864.0 * h)));
        h = h * (1.0 - double(cal.dig_H1) * h / 524288.0);
        RH_pct = max(0, min(100, h));
    end
end
