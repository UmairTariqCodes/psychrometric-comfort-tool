function cal = readCalibration(sensor)
    % READCALIBRATION Read BME280 factory calibration registers over I2C (requires MATLAB Support Package for Arduino).
    %   Part of the 'bme280' package - call as bme280.readCalibration(...).
    %
    % Read temperature and pressure calibration: registers 0x88-0xA1 (26 bytes)
    tpCal = zeros(1, 26, 'uint8');
    for k = 0:25
        tpCal(k+1) = readRegister(sensor, uint8(0x88 + k), 'uint8');
    end

    cal.dig_T1 = typecast(uint8(tpCal(1:2)), 'uint16');
    cal.dig_T2 = typecast(uint8(tpCal(3:4)), 'int16');
    cal.dig_T3 = typecast(uint8(tpCal(5:6)), 'int16');

    cal.dig_P1 = typecast(uint8(tpCal(7:8)), 'uint16');
    cal.dig_P2 = typecast(uint8(tpCal(9:10)), 'int16');
    cal.dig_P3 = typecast(uint8(tpCal(11:12)), 'int16');
    cal.dig_P4 = typecast(uint8(tpCal(13:14)), 'int16');
    cal.dig_P5 = typecast(uint8(tpCal(15:16)), 'int16');
    cal.dig_P6 = typecast(uint8(tpCal(17:18)), 'int16');
    cal.dig_P7 = typecast(uint8(tpCal(19:20)), 'int16');
    cal.dig_P8 = typecast(uint8(tpCal(21:22)), 'int16');
    cal.dig_P9 = typecast(uint8(tpCal(23:24)), 'int16');

    % Humidity calibration: H1 at 0xA1
    cal.dig_H1 = readRegister(sensor, uint8(0xA1), 'uint8');

    % H2-H6 at registers 0xE1-0xE7
    hCal = zeros(1, 7, 'uint8');
    for k = 0:6
        hCal(k+1) = readRegister(sensor, uint8(0xE1 + k), 'uint8');
    end

    cal.dig_H2 = typecast(uint8(hCal(1:2)), 'int16');
    cal.dig_H3 = hCal(3);
    cal.dig_H4 = int16(bitor(bitshift(int16(hCal(4)), 4), bitand(int16(hCal(5)), int16(0x0F))));
    cal.dig_H5 = int16(bitor(bitshift(int16(hCal(6)), 4), bitand(bitshift(int16(hCal(5)), -4), int16(0x0F))));
    cal.dig_H6 = typecast(uint8(hCal(7)), 'int8');
end
