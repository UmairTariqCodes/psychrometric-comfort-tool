classdef PsychroTest < matlab.unittest.TestCase
    % PSYCHROTEST Unit tests for the +psychro package against reference values.
    %
    % Reference values are from the ASHRAE Handbook - Fundamentals
    % (saturation pressure table) and standard textbook state points
    % at sea-level pressure (101 325 Pa).
    %
    % Run from the matlab/ folder:
    %   results = runtests('tests');
    %   table(results)

    properties (Constant)
        P = 101325;   % Pa
        SI = 2;
        IP = 1;
    end

    methods (TestClassSetup)
        function addSourceToPath(testCase)
            here = fileparts(mfilename('fullpath'));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(here, '..')));
        end
    end

    methods (Test)
        function saturationPressureMatchesAshraeTable(testCase)
            % T [C] -> Pws [Pa], ASHRAE Fundamentals Table 3
            T   = [-10     0       20      30      40];
            ref = [259.90  611.21  2339.3  4246.9  7384.9];
            for k = 1:numel(T)
                Pws = psychro.saturationPressure(T(k), testCase.SI);
                testCase.verifyEqual(Pws, ref(k), 'RelTol', 0.005, ...
                    sprintf('Pws at %g C', T(k)));
            end
        end

        function saturationPressureImperialConsistent(testCase)
            % 68 F == 20 C ; IP output in psia
            Pws_IP = psychro.saturationPressure(68, testCase.IP);
            Pws_SI = psychro.saturationPressure(20, testCase.SI);
            testCase.verifyEqual(Pws_IP, Pws_SI * 0.0001450377, 'RelTol', 1e-9);
        end

        function propertiesAt20C50RH(testCase)
            % Textbook state point: 20 C, 50 % RH, sea level
            Pws = psychro.saturationPressure(20, testCase.SI);
            W   = psychro.humidityRatio(0.5 * Pws, testCase.P, testCase.SI);
            p   = psychro.calculateProperties(20, W, testCase.P, testCase.SI);

            testCase.verifyEqual(W,     0.00726, 'AbsTol', 5e-5);   % kg/kg
            testCase.verifyEqual(p.RH,  0.50,    'AbsTol', 1e-3);
            testCase.verifyEqual(p.Tdp, 9.3,     'AbsTol', 0.2);    % C
            testCase.verifyEqual(p.Twb, 13.7,    'AbsTol', 0.2);    % C
            testCase.verifyEqual(p.h,   38.5,    'AbsTol', 0.3);    % kJ/kg
            testCase.verifyEqual(p.v,   0.8395,  'AbsTol', 2e-3);   % m3/kg
        end

        function wetBulbRoundTrip(testCase)
            % W from (Tdb, Twb) then Twb back from (Tdb, W)
            W   = psychro.humidityRatioFromWetBulb(30, 20, testCase.P, testCase.SI);
            Twb = psychro.calculateWetBulb(30, W, testCase.P, testCase.SI);
            testCase.verifyEqual(Twb, 20, 'AbsTol', 0.05);
        end

        function liveSensorWetBulbMatchesChart(testCase)
            % Regression test: the live-sensor tab must agree with the chart
            Pws = psychro.saturationPressure(20, testCase.SI);
            W   = psychro.humidityRatio(0.5 * Pws, testCase.P, testCase.SI);
            testCase.verifyEqual(psychro.wetBulbFromTW(20, W, testCase.P), 13.7, 'AbsTol', 0.2);
        end

        function enthalpyRoundTrip(testCase)
            p = psychro.calculateProperties(25, 0.010, testCase.P, testCase.SI);
            W = psychro.humidityRatioFromEnthalpy(p.h, 25, testCase.SI);
            testCase.verifyEqual(W, 0.010, 'AbsTol', 1e-6);
        end

        function solveFromEnthalpyAndRHRoundTrip(testCase)
            p = psychro.calculateProperties(24, 0.009, testCase.P, testCase.SI);
            [T, W] = psychro.solveFromEnthalpyAndRH(p.h, p.RH, testCase.P, testCase.SI);
            testCase.verifyEqual(T, 24, 'AbsTol', 0.1);
            testCase.verifyEqual(W, 0.009, 'AbsTol', 1e-4);
        end

        function adpLiesOnSaturationCurve(testCase)
            [T_adp, W_adp] = psychro.findADP(24, 0.0093, 0.75, testCase.P, testCase.SI);
            testCase.verifyLessThan(T_adp, 24);
            Ws = psychro.humidityRatio(psychro.saturationPressure(T_adp, 2), testCase.P, 2);
            testCase.verifyEqual(W_adp, Ws, 'AbsTol', 1e-9);
        end

        function comfortRangeReferencePoints(testCase)
            [lo, hi] = psychro.getComfortTempRange(0.5, 1.1, 0.1, testCase.SI);
            testCase.verifyEqual([lo hi], [23.0 26.5], 'AbsTol', 1e-9);
            [lo, hi] = psychro.getComfortTempRange(1.0, 1.1, 0.1, testCase.SI);
            testCase.verifyEqual([lo hi], [20.0 24.0], 'AbsTol', 1e-9);
        end

        function pmvIsZeroAtNeutralTemperature(testCase)
            pmv = psychro.estimatePMV(24.75, 0.5, 0.5, 1.1, 0.1, testCase.SI);
            testCase.verifyEqual(pmv, 0, 'AbsTol', 1e-9);
        end
    end
end
