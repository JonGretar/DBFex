defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading version (0xf5) FoxPro with memo file" do
    test "it errors on unsupported version" do
      exception = DBF.DatabaseError.new(:unsupported_version, "FoxPro with memo file")
      assert {:error, exception} == DBF.open("test/dbf_files/dbase_f5.dbf")
    end
  end

  describe "When reading version (02) FoxBase" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_02.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x02
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1900-01-01]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 9
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

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

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

  describe "When reading version (8b) dBase IV with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_8b.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "reads the version", context do
      assert context.db.version == 0x8b
    end

    test "reads the last updated date", context do
      assert context.db.last_updated == ~D[2000-06-12]
    end

    test "reads the number of records", context do
      assert context.db.number_of_records == 10
    end

    test "Gets the first record", context do
      assert DBF.get(context.db, 0)
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
