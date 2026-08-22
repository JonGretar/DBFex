defmodule DBase3Test do
  use ExUnit.Case
  doctest DBF

  test "version (03) dBase III tables reject duplicate decoded field names" do
    assert {:error,
            %DBF.DatabaseError{
              reason: :invalid_schema,
              cause: :duplicate_field_name,
              context: %{field_name: "Point_ID"}
            }} = DBF.open("test/dbf_files/dbase_03.dbf")
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
        "DESC" =>
          "Our Original assortment...a little taste of heaven for everyone.  Let us\r\nselect a special assortment of our chocolate and pastel favorites for you.\r\nEach petit four is its own special hand decorated creation. Multi-layers of\r\nmoist cake with combinations of specialty fillings create memorable cake\r\nconfections. Varietes include; Luscious Lemon, Strawberry Hearts, White\r\nChocolate, Mocha Bean, Roasted Almond, Triple Chocolate, Chocolate Hazelnut,\r\nGrand Orange, Plum Squares, Milk chocolate squares, and Rasp",
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
