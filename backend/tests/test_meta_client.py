from app.meta_client import parse_boxes


def test_parse_boxes_with_and_without_confidence():
    raw = (
        "<0f>1<|box;x1=211;y1=228;x2=270;y2=254;w=320;h=334;c=0.96|><|mask;x=0;y=0;data=27,60,~abc|>,"
        "2<|box;x1=10;y1=20;x2=30;y2=40;w=320;h=334|><|mask;x=0;y=0;data=5,5,~x|>"
    )
    boxes = parse_boxes(raw)
    assert len(boxes) == 2
    assert (boxes[0].x1, boxes[0].y2, boxes[0].confidence) == (211, 254, 0.96)
    assert boxes[1].confidence is None


def test_parse_boxes_empty_output_is_zero_matches():
    assert parse_boxes("") == []
