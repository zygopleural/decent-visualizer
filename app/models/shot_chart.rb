# frozen_string_literal: true

class ShotChart
  extend Memoist

  DATA_LABELS_TO_IGNORE = %w[espresso_resistance espresso_resistance_weight espresso_state_change].freeze
  MAX_RESISTANCE_VALUE = 19
  MIN_CONDUCTANCE_DIFF_VALUE = -5
  GAUSSIAN_MULTIPLIERS = [0.048297, 0.08393, 0.124548, 0.157829, 0.170793, 0.157829, 0.124548, 0.08393, 0.048297].freeze

  attr_reader :shot, :user, :to_fahrenheit, :chart_settings, :processed_shot_data

  def initialize(shot, user = nil)
    @shot = shot
    @user = user
    @to_fahrenheit = user&.wants_fahrenheit?
    @chart_settings = ChartSettings.new(user)
    prepare_chart_data
    @temperature_data, @main_data = processed_shot_data.sort.partition { |key, _v| key.include?("temperature") }
  end

  def shot_chart
    for_highcharts(@main_data)
  end

  def temperature_chart
    for_highcharts(@temperature_data)
  end

  memoize def stages
    indices = shot.information.data.key?("espresso_state_change") ? stages_from_state_change(shot.information.data["espresso_state_change"]) : detect_stages_from_data(shot.information.data)
    processed_shot_data.first.second.values_at(*indices).map { |d| {value: d.first} }
  end

  private

  def prepare_chart_data
    @processed_shot_data = process_data(shot)
    @processed_shot_data["espresso_resistance"] = resistance_chart(@processed_shot_data["espresso_pressure"], @processed_shot_data["espresso_flow"])
    @processed_shot_data["espresso_conductance"] = conductance_chart(@processed_shot_data["espresso_pressure"], @processed_shot_data["espresso_flow"])
    @processed_shot_data["espresso_conductance_derivative"] = conductance_derivative_chart(@processed_shot_data["espresso_conductance"])
  end

  def for_highcharts(data)
    data.filter_map do |label, d|
      setting = chart_settings.for_label(label)
      next if setting.blank?

      {
        name: setting["title"],
        data: d,
        color: setting["color"],
        visible: !setting["hidden"],
        dashStyle: setting["dashed"] ? "Dash" : "Solid",
        tooltip: {
          valueDecimals: 2,
          valueSuffix: setting["suffix"]
        },
        opacity: setting["opacity"] || 1,
        type: setting["type"] == "spline" ? "spline" : "line"
      }
    end
  end

  def resistance_chart(pressure_data, flow_data)
    pressure_data.map.with_index do |(t, v), i|
      f = flow_data[i].second.to_f
      if f.zero?
        v = nil
      else
        r = v.to_f / (f**2)
        v = r > MAX_RESISTANCE_VALUE ? nil : r
      end
      [t, v]
    end
  end

  def conductance_chart(pressure_data, flow_data)
    pressure_data.map.with_index do |(t, v), i|
      f = flow_data[i].second.to_f
      if v.zero?
        v = nil
      else
        c = (f**2) / v.to_f
        v = c > MAX_RESISTANCE_VALUE ? nil : c
      end
      [t, v]
    end
  end

  def conductance_derivative_chart(conductance_data)
    derivative = []
    conductance_data.each_cons(2) do |(t1, v1), (t2, v2)|
      v = if v1.nil? || v2.nil?
        nil
      else
        ((v2 - v1) / ((t2 - t1) / 1000)) * 10
      end
      derivative << [t1, v]
    end

    smoothed = []
    4.times do
      derivative << [nil, nil]
      smoothed << [nil, nil]
    end

    derivative.each_cons(9) do |data|
      values = data.map(&:last)
      value = values.zip(GAUSSIAN_MULTIPLIERS).sum { |v, m| v.to_f * m }
      value = nil if value > MAX_RESISTANCE_VALUE || value < MIN_CONDUCTANCE_DIFF_VALUE
      smoothed << [data[4].first, value]
    end
    smoothed
  end

  def stages_from_state_change(data)
    indices = []
    current = data.find { |s| !s.to_i.zero? }
    data.each.with_index do |s, i|
      next if s.to_i.zero? || s == current

      indices << i
      current = s
    end
    indices
  end

  def process_data(shot, label_suffix: nil)
    timeframe = shot.information.timeframe
    timeframe_count = timeframe.count
    timeframe_last = timeframe.last.to_f
    timeframe_diff = (timeframe_last + timeframe.first.to_f) / timeframe.count.to_f
    in_fahrenheit = shot.information.fahrenheit?
    shot.information.data.filter_map do |label, data|
      next if DATA_LABELS_TO_IGNORE.include?(label)

      times10 = label == "espresso_water_dispensed"
      temperature_label = label.include?("temperature")
      data = data.map.with_index do |v, i|
        t = i < timeframe_count ? timeframe[i] : timeframe_last + ((i - timeframe_count + 1) * timeframe_diff)
        v = v.to_f
        v *= 10 if times10
        if temperature_label
          if to_fahrenheit && !in_fahrenheit
            v = (v * 9 / 5) + 32
          elsif !to_fahrenheit && in_fahrenheit
            v = (v - 32) * 5 / 9
          end
        end
        v = nil if v.negative?
        [t.to_f * 1000, v]
      end
      [[label, label_suffix].join, data]
    end.to_h
  end

  def detect_stages_from_data(data)
    indices = []
    data.select { |label, _| label.end_with?("_goal") }.each do |_, d|
      d = d.map(&:to_f)
      d.each.with_index do |a, i|
        next if i < 5

        b = d[i - 1]
        c = d[i - 2]
        diff2 = ((a - b) - (b - c))
        indices << i if diff2.abs > 0.1
      end
    end

    if indices.any?
      indices = indices.sort.uniq
      selected = [indices.first]
      indices.each do |index|
        selected << index if (index - selected.last) > 5
      end
    end
    selected
  end
end
