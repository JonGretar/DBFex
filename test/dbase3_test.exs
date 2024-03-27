defmodule DBase3Test do
  use ExUnit.Case
  doctest DBF

  describe "When reading version (03) dBase III without memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_03.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x03
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1905-07-13]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 14
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "the first record is all that we wanted", context do
      record = %{
        "Circular_D" => "12",
        "Comments" => "",
        "Condition" => "Good",
        "Corr_Type" => "Postprocessed Code",
        "Data_Dicti" => "MS4",
        "Datafile" => "050712TR2819.cor",
        "Date_Visit" => ~D[2005-07-12],
        "Easting" => 2212577.192,
        "Feat_Name" => "Driveway",
        "Filt_Pos" => 2.0,
        "Flow_prese" => "no",
        "GPS_Date" => ~D[2005-07-12],
        "GPS_Height" => 1131.323,
        "GPS_Second" => 226625.0,
        "GPS_Time" => "10:56:52am",
        "GPS_Week" => 1331.0,
        "Horz_Prec" => 1.3,
        "Max_HDOP" => 2.0,
        "Max_PDOP" => 5.2,
        "Non_circul" => "",
        "Northing" => 557904.898,
        "Point_ID" => 401.0,
        "Rcvr_Type" => "GeoXT",
        "Shape" => "circular",
        "Std_Dev" => 0.897088,
        "Time" => "10:56:30am",
        "Type" => "CMP",
        "Unfilt_Pos" => 2.0,
        "Update_Sta" => "New",
        "Vert_Prec" => 3.1
      }
      assert {:record, record} == DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

  describe "When reading version (83) dBase III with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_83.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x83
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[2003-12-18]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 67
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "the first record is all that we wanted", context do
      record = %{
        "ACTIVE" => true,
        "AGRPCOUNT" => 0.0,
        "CATCOUNT" => 2.0,
        "CODE" => "1",
        "COST" => 0.0,
        "DESC" => "Our Original assortment...a little taste of heaven for everyone.  Let us\r\nselect a special assortment of our chocolate and pastel favorites for you.\r\nEach petit four is its own special hand decorated creation. Multi-layers of\r\nmoist cake with combinations of specialty fillings create memorable cake\r\nconfections. Varietes include; Luscious Lemon, Strawberry Hearts, White\r\nChocolate, Mocha Bean, Roasted Almond, Triple Chocolate, Chocolate Hazelnut,\r\nGrand Orange, Plum Squares, Milk chocolate squares, and Rasp",
        "ID" => 87.0,
        "IMAGE" => "graphics/00000001/1.jpg",
        "NAME" => "Assorted Petits Fours",
        "ORDER" => 87.0,
        "PGRPCOUNT" => 0.0,
        "PRICE" => 0.0,
        "TAXABLE" => true,
        "THUMBNAIL" => "graphics/00000001/t_1.jpg",
        "WEIGHT" => 5.51
      }
      assert {:record, record} == DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end


end
