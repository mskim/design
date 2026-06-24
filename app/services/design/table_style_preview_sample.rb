module Design
  class TableStylePreviewSample
    SAMPLE = {
      rows: [
        { kind: :header, cells: [ { text: "Region" }, { text: "Population" }, { text: "Area (km²)" } ] },
        { kind: :body,   cells: [ { text: "Seoul" }, { text: "9.7M" }, { text: "605" } ] },
        { kind: :body,   cells: [ { text: "Busan" }, { text: "3.4M" }, { text: "770" } ] },
        { kind: :body,   cells: [ { text: "Daegu" }, { text: "2.4M" }, { text: "884" } ] }
      ]
    }.freeze
  end
end
